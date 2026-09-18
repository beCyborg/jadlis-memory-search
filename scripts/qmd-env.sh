#!/usr/bin/env bash
# Shared environment for jadlis-memory-search scripts. SOURCED, never executed.
# Must print nothing: qmd-mcp.sh sources it before speaking the stdio protocol.
# Works with macOS /bin/bash 3.2 (launchd) — no mapfile, no associative arrays.

_jms_path_add() {  # append dir to _JMS_P unless already present
  [ -n "$1" ] || return 0
  case ":$_JMS_P:" in *":$1:"*) return 0 ;; esac
  if [ -z "$_JMS_P" ]; then _JMS_P="$1"; else _JMS_P="$_JMS_P:$1"; fi
}

_jms_node_manager_dirs() {  # one bin dir per line, newest version first where it matters
  local d
  # nvm: newest installed version
  d="${NVM_DIR:-$HOME/.nvm}/versions/node"
  if [ -d "$d" ]; then
    ls -1 "$d" 2>/dev/null | sed 's/^v//' | sort -t. -k1,1nr -k2,2nr -k3,3nr | head -1 \
      | while IFS= read -r v; do [ -n "$v" ] && [ -d "$d/v$v/bin" ] && echo "$d/v$v/bin"; done
  fi
  # fnm: default alias
  for d in "${FNM_DIR:-}" "$HOME/Library/Application Support/fnm" "$HOME/.local/share/fnm" "$HOME/.fnm"; do
    [ -n "$d" ] && [ -d "$d/aliases/default/bin" ] && { echo "$d/aliases/default/bin"; break; }
  done
  # volta
  d="${VOLTA_HOME:-$HOME/.volta}/bin"
  [ -d "$d" ] && echo "$d"
  return 0
}

_JMS_P=""
if [ "${JMS_SKIP_DEFAULT_PATH:-0}" != "1" ]; then
  _jms_path_add /opt/homebrew/bin
  _jms_path_add /usr/local/bin
  _jms_path_add "$HOME/.local/bin"
  while IFS= read -r _jms_d; do _jms_path_add "$_jms_d"; done < <(_jms_node_manager_dirs)
fi
_JMS_OLDIFS=$IFS; IFS=:
for _jms_d in ${PATH:-}; do _jms_path_add "$_jms_d"; done
IFS=$_JMS_OLDIFS
for _jms_d in /usr/bin /bin /usr/sbin /sbin; do _jms_path_add "$_jms_d"; done
export PATH="$_JMS_P"
unset _JMS_P _JMS_OLDIFS _jms_d

export QMD_EMBED_CONTEXT_SIZE="${QMD_EMBED_CONTEXT_SIZE:-506}"
export QMD_EMBED_PARALLELISM="${QMD_EMBED_PARALLELISM:-1}"

JMS_DATA="${JMS_DATA:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/jadlis-memory-search-jadlis}}"
JMS_LOGS="$JMS_DATA/logs"
JMS_STATE="$JMS_DATA/state"
export JMS_DATA JMS_LOGS JMS_STATE
[ "${JMS_NO_MKDIR:-0}" = "1" ] || mkdir -p "$JMS_LOGS" "$JMS_STATE" 2>/dev/null

jms_qmd_config() {
  local dir
  if [ -n "${QMD_CONFIG_DIR:-}" ]; then dir="$QMD_CONFIG_DIR"
  elif [ -n "${XDG_CONFIG_HOME:-}" ]; then dir="$XDG_CONFIG_HOME/qmd"
  else dir="$HOME/.config/qmd"; fi
  echo "$dir/index.yml"
}

# Collection paths from index.yml: `    path: …` lines (4-space indent = collection
# property; deeper keys are contexts). Quotes stripped. Empty when no file.
jms_collection_paths() {
  local cfg
  cfg="$(jms_qmd_config)"
  [ -f "$cfg" ] || return 0
  awk -v q="'" '
    /^    path:[[:space:]]*/ {
      v = $0
      sub(/^    path:[[:space:]]*/, "", v)
      sub(/[[:space:]]+$/, "", v)
      if (v ~ /^".*"$/) { v = substr(v, 2, length(v) - 2); gsub(/\\"/, "\"", v); gsub(/\\\\/, "\\", v) }
      else if (substr(v, 1, 1) == q && substr(v, length(v), 1) == q && length(v) >= 2) { v = substr(v, 2, length(v) - 2); gsub(q q, q, v) }
      if (v != "") print v
    }' "$cfg"
}

# Keep logs small: over 5 MB → keep the last 1000 lines.
jms_rotate() {
  local f="$1" size
  [ -f "$f" ] || return 0
  size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
  if [ -n "$size" ] && [ "$size" -gt 5242880 ]; then
    tail -n 1000 "$f" > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
  fi
  return 0
}

jms_log() {
  local f="$1"; shift
  jms_rotate "$f"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$f"
}

jms_node_major() {
  local v
  command -v node >/dev/null 2>&1 || return 1
  v="$(node -v 2>/dev/null)"; v="${v#v}"; v="${v%%.*}"
  case "$v" in ''|*[!0-9]*) return 1 ;; esac
  echo "$v"
}

jms_node_ok() {
  local m
  m="$(jms_node_major)" || return 1
  [ "$m" -ge 22 ]
}

jms_qmd_ok() {
  command -v qmd >/dev/null 2>&1
}

# qmd walks up from cwd looking for a project-local .qmd/ config; run it from /
# so the global index.yml is always the one in use.
jms_qmd() {
  ( cd / && exec qmd "$@" )
}

jms_strip_ansi() {
  sed "s/$(printf '\033')\[[0-9;?]*[A-Za-z]//g"
}
