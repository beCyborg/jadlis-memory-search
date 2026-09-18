#!/usr/bin/env bash
# Onboarding step 1 in one call: prerequisites, qmd config, existing collections,
# Obsidian vault candidates and stray project-local .qmd/ dirs. Read-only.
# Usage: preflight.sh [<dir to start the .qmd/.obsidian walk from>]   (default: $PWD)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
START="${1:-$PWD}"
export JMS_NO_MKDIR=1
. "$HERE/qmd-env.sh"

echo "os: $(uname -sm)"
if m="$(jms_node_major)"; then
  if [ "$m" -ge 22 ]; then echo "node: $(node -v) ok"; else echo "node: $(node -v) TOO_OLD (нужна 22+)"; fi
else
  echo "node: MISSING"
fi
if jms_qmd_ok; then echo "qmd: $(jms_qmd --version 2>/dev/null | head -1)"; else echo "qmd: MISSING"; fi
echo "disk_free: $(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
echo "models_cached: $(ls "$HOME/.cache/qmd/models" 2>/dev/null | grep -c embeddinggemma) (embeddinggemma)"

cfg="$(jms_qmd_config)"
if [ -f "$cfg" ]; then echo "qmd_config: $cfg"; else echo "qmd_config: $cfg (нет файла)"; fi
echo "collections:"
if jms_qmd_ok && [ -f "$cfg" ]; then
  jms_qmd collection list 2>/dev/null | jms_strip_ansi | sed 's/^/  /'
fi
paths="$(jms_collection_paths)"
[ -n "$paths" ] && printf '%s\n' "$paths" | sed 's/^/  path: /'

# Obsidian registry → one line per vault: path, open flag
echo "vaults:"
for f in "$HOME/Library/Application Support/obsidian/obsidian.json" "$HOME/.config/obsidian/obsidian.json"; do
  [ -f "$f" ] || continue
  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      for (const v of Object.values(j.vaults || {})) {
        if (v && v.path && fs.existsSync(v.path)) console.log("  " + v.path + (v.open ? "  (open)" : ""));
      }' "$f" 2>/dev/null
  else
    grep -o '"path":"[^"]*"' "$f" | sed 's/^"path":"//; s/"$//; s/^/  /'
  fi
done

# Walk up from START: nearest .obsidian = current vault; any .qmd/ = local config that would shadow the global one
d="$(cd "$START" 2>/dev/null && pwd)" || d="$START"
cwd_vault=""
while [ -n "$d" ]; do
  [ -z "$cwd_vault" ] && [ -d "$d/.obsidian" ] && cwd_vault="$d"
  [ -d "$d/.qmd" ] && echo "local_qmd: $d/.qmd"
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done
echo "cwd_vault: ${cwd_vault:-none}"
