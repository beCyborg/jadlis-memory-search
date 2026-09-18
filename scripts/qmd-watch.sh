#!/usr/bin/env bash
# Poller: every POLL s look for *.md newer than the stamp in every collection path;
# on a change wait DEBOUNCE s and reindex; force a full reindex every SWEEP s
# (qmd update is hash-based: catches deletions, renames and synced files with old mtimes).
# Runs forever under launchd KeepAlive — never exits on "nothing to do".
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/qmd-env.sh"

POLL="${POLL:-60}"
DEBOUNCE="${DEBOUNCE:-20}"
SWEEP="${SWEEP:-3600}"
LOG="$JMS_LOGS/watch.log"
STAMP="$JMS_STATE/watch.stamp"   # mtime = start of the last successful index run
ALIVE="$JMS_STATE/watch.alive"   # touched every loop → health probe
REINDEX="$HERE/qmd-reindex.sh"

[ -f "$STAMP" ] || touch -t 197001010000 "$STAMP"

changed() {
  local p paths=()
  while IFS= read -r p; do
    [ -d "$p" ] && paths+=("$p")
  done < <(jms_collection_paths)
  [ "${#paths[@]}" -gt 0 ] || return 1
  [ -n "$(find "${paths[@]}" -name '*.md' -type f -newer "$STAMP" \
          -not -path '*/.*' -print -quit 2>/dev/null)" ]
}

reindex() {  # $1 = log label, $2 = reindex reason
  local out rc
  touch "$STAMP.next"   # changes landing during the run stay newer for the next poll
  out="$(bash "$REINDEX" "$2" 2>&1)"; rc=$?
  jms_log "$LOG" "$1"
  [ -n "$out" ] && printf '%s\n' "$out" >> "$LOG"
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'уже идёт переиндексация'; then
    mv -f "$STAMP.next" "$STAMP"
  else
    rm -f "$STAMP.next"   # retry on the next poll
  fi
}

jms_log "$LOG" "watcher start (poll ${POLL}s, debounce ${DEBOUNCE}s, sweep ${SWEEP}s)"
last_sweep=$(date +%s)
last_nocoll=0
while true; do
  touch "$ALIVE"
  jms_rotate "$LOG"
  now=$(date +%s)
  if [ -z "$(jms_collection_paths)" ]; then
    if [ $(( now - last_nocoll )) -ge 3600 ]; then
      jms_log "$LOG" "no collections in $(jms_qmd_config) — sleeping"
      last_nocoll=$now
    fi
  elif changed; then
    sleep "$DEBOUNCE"
    reindex "change detected" watch
    last_sweep=$(date +%s)
  elif [ $(( now - last_sweep )) -ge "$SWEEP" ]; then
    reindex "hourly sweep" sweep
    last_sweep=$(date +%s)
  fi
  sleep "$POLL"
done
