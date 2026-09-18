#!/usr/bin/env bash
# One reindex pass: qmd update → qmd embed when vectors are pending.
# Usage: qmd-reindex.sh <setup|hook|watch|sweep|manual|full> [--log <file>]
#   full   → update, then force re-embed of everything (qmd embed -f)
#   --log  → also stream progress (stdout+stderr) into <file>, appending
# Prints one summary line to stdout; appends a block to $JMS_LOGS/reindex.log.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/qmd-env.sh"

REASON="manual"; LOGFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --log) LOGFILE="${2:-}"; shift 2 ;;
    --log=*) LOGFILE="${1#--log=}"; shift ;;
    setup|hook|watch|sweep|manual|full) REASON="$1"; shift ;;
    *) shift ;;
  esac
done

if [ -n "$LOGFILE" ]; then
  mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
  jms_rotate "$LOGFILE"
  exec > >(tee -a "$LOGFILE") 2>&1
fi
say() { [ -n "$LOGFILE" ] && echo "$(date '+%H:%M:%S') $*"; return 0; }

LOG="$JMS_LOGS/reindex.log"
LOCK="$JMS_STATE/reindex.lock"
NEXT="$JMS_STATE/last-index.next"
LAST="$JMS_STATE/last-index"

# qmd prefers a project-local .qmd/ found upward from cwd; run from / so the
# global index.yml is always the one in use.
cd / || exit 1

if [ -z "$(jms_collection_paths)" ]; then
  echo "нет коллекций — сначала /memory-search-setup"
  exit 0
fi
if ! jms_qmd_ok; then
  echo "qmd не найден — установите: npm install -g @tobilu/qmd" >&2
  exit 127
fi

lock_is_stale() {
  local pid
  [ -d "$LOCK" ] || return 1
  [ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ] && return 0
  pid="$(cat "$LOCK/pid" 2>/dev/null)"
  [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null && return 0
  return 1
}

if ! mkdir "$LOCK" 2>/dev/null; then
  if lock_is_stale; then
    rm -rf "$LOCK"
    mkdir "$LOCK" 2>/dev/null || { echo "уже идёт переиндексация"; exit 0; }
  else
    echo "уже идёт переиндексация"
    exit 0
  fi
fi
echo $$ > "$LOCK/pid"
# NEXT is renamed to LAST on success, so removing it on exit only matters on failure.
kill_tree() {  # TERM every descendant of pid $1 (qmd must not outlive the lock)
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; kill -TERM "$c" 2>/dev/null; done
}
trap 'rm -rf "$LOCK"; rm -f "$NEXT"' EXIT
trap 'kill_tree $$; exit 130' INT
trap 'kill_tree $$; exit 143' TERM
trap 'kill_tree $$; exit 129' HUP

# Keep the last CR-segment of each line (progress bars), drop ANSI codes and
# flush every line so the log shows live progress (tr/sed would block-buffer).
stream_filter() {
  awk -v esc="$(printf '\033')" -v cr="$(printf '\r')" '
    { n = split($0, a, cr); v = a[n]; if (v == "" && n > 1) v = a[n - 1]
      gsub(esc "\\[[0-9;?]*[A-Za-z]", "", v); print v; fflush() }'
}

# run_qmd <capture-file> <qmd args…> — capture output; stream it too with --log.
# Runs in the background + wait, so a trapped signal interrupts it immediately.
run_qmd() {
  local f="$1"; shift
  if [ -n "$LOGFILE" ]; then
    rm -f "$f.rc"
    ( qmd "$@" 2>&1; echo $? > "$f.rc" ) | stream_filter | tee "$f" &
    wait $!
    return "$(cat "$f.rc" 2>/dev/null || echo 1)"
  fi
  qmd "$@" > "$f" 2>&1 &
  wait $!
}

jms_rotate "$LOG"
t0=$(date +%s)
touch "$NEXT"   # changes landing during the run stay newer than last-index

say "reindex $REASON: qmd update"
run_qmd "$LOCK/update.out" update; up_rc=$?
up_out="$(cat "$LOCK/update.out" 2>/dev/null)"
# Sum the per-collection "Indexed: N new, N updated, N unchanged, N removed" lines.
up_line="$(printf '%s\n' "$up_out" | jms_strip_ansi | awk '
  /^Indexed: / { f = 1; n += $2; u += $4; c += $6; r += $8 }
  END { if (f) printf "Indexed: %d new, %d updated, %d unchanged, %d removed", n, u, c, r }')"
if [ "$up_rc" -ne 0 ] || [ -z "$up_line" ]; then
  err_line="$(printf '%s\n' "$up_out" | jms_strip_ansi | grep -iE 'error|rror' | tail -1)"
  up_line="${up_line:+$up_line; }${err_line:-qmd update rc=$up_rc}"
fi

emb_line=""; emb_rc=0
if [ "$up_rc" -eq 0 ]; then
  if [ "$REASON" = "full" ]; then
    emb_args="embed -f --timeout 0"
  elif printf '%s\n' "$up_out" | grep -qiE 'need vectors|need embedding' \
       || qmd status 2>/dev/null | grep -qiE 'pending|need embedding|need vectors'; then
    emb_args="embed --timeout 0"
  else
    emb_args=""
  fi
  if [ -n "$emb_args" ]; then
    say "reindex $REASON: qmd $emb_args"
    run_qmd "$LOCK/embed.out" $emb_args; emb_rc=$?
    emb_line="$(tr '\r' '\n' < "$LOCK/embed.out" | jms_strip_ansi | grep -E 'Done|Error|error' | tail -1)"
    [ -n "$emb_line" ] || emb_line="qmd embed rc=$emb_rc"
  fi
fi

st="$(qmd status 2>/dev/null | jms_strip_ansi)"
total="$(printf '%s\n' "$st" | awk '/^ *Total:/ {print $2; exit}')"
vectors="$(printf '%s\n' "$st" | awk '/^ *Vectors:/ {print $2; exit}')"
pending="$(printf '%s\n' "$st" | awk '/^ *Pending:/ {print $2; exit}')"
counts="Total ${total:-?} Vectors ${vectors:-?}"
[ -n "$pending" ] && counts="$counts Pending $pending"
secs=$(( $(date +%s) - t0 ))

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') $REASON"
  echo "$up_line"
  [ -n "$emb_line" ] && echo "$emb_line"
  printf '%s\n' "$st" | grep -E 'Total|Vectors|Pending' | tr -s ' ' | tr '\n' ' '
  echo "(${secs}s)"
} >> "$LOG" 2>&1

summary="reindex $REASON: $up_line"
[ -n "$emb_line" ] && summary="$summary | $emb_line"
echo "$summary | $counts (${secs}s)"

[ "$up_rc" -ne 0 ] && exit "$up_rc"
# On embed failure keep last-index old so the next hook/poll retries.
[ "$emb_rc" -ne 0 ] && exit "$emb_rc"
mv -f "$NEXT" "$LAST"
exit 0
