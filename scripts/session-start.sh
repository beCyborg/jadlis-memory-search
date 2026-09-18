#!/usr/bin/env bash
# SessionStart hook (async). Silent unless it starts a background reindex. Always exit 0.
set -u
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
. "$ROOT/scripts/qmd-env.sh" 2>/dev/null || exit 0

BIN="$JMS_DATA/bin"
HOOK_LOG="$JMS_LOGS/hook.log"
LABEL="com.jadlis.memory-search.watch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# 1. Keep the launchd copies in DATA/bin in sync with the (possibly updated) plugin root.
mkdir -p "$BIN" 2>/dev/null
synced=0
for f in qmd-env.sh qmd-reindex.sh qmd-watch.sh; do
  [ -f "$ROOT/scripts/$f" ] || continue
  if ! cmp -s "$ROOT/scripts/$f" "$BIN/$f"; then
    cp -f "$ROOT/scripts/$f" "$BIN/$f" 2>/dev/null && chmod +x "$BIN/$f" 2>/dev/null
    synced=1
  fi
done
if [ "$synced" -eq 1 ] && [ -f "$PLIST" ] && command -v launchctl >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
  jms_log "$HOOK_LOG" "scripts synced to $BIN, watcher restarted"
fi

# 2. Nothing configured yet.
paths=()
while IFS= read -r p; do
  [ -d "$p" ] && paths+=("$p")
done < <(jms_collection_paths)
[ "${#paths[@]}" -gt 0 ] || exit 0

# 3. A live poller keeps the index fresh on its own.
ALIVE="$JMS_STATE/watch.alive"
[ -n "$(find "$ALIVE" -maxdepth 0 -mmin -10 2>/dev/null)" ] && exit 0

# 4. Installed but not alive → note it for /memory-search status.
[ -f "$PLIST" ] && jms_log "$HOOK_LOG" "watch agent installed but watch.alive is stale or missing"

# 5. Freshness check.
LAST="$JMS_STATE/last-index"
if [ -f "$LAST" ]; then
  [ -n "$(find "${paths[@]}" -name '*.md' -type f -newer "$LAST" -not -path '*/.*' -print -quit 2>/dev/null)" ] || exit 0
fi

# A reindex already running (poller, setup, manual) will pick the change up.
RLOCK="$JMS_STATE/reindex.lock"
[ -d "$RLOCK" ] && [ -z "$(find "$RLOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ] && exit 0

HLOCK="$JMS_STATE/hook.lock"
if ! mkdir "$HLOCK" 2>/dev/null; then
  [ -n "$(find "$HLOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ] || exit 0
  rm -rf "$HLOCK"
  mkdir "$HLOCK" 2>/dev/null || exit 0
fi

REINDEX="$BIN/qmd-reindex.sh"
[ -f "$REINDEX" ] || REINDEX="$ROOT/scripts/qmd-reindex.sh"
jms_rotate "$HOOK_LOG"
nohup bash -c 'bash "$1" hook; rm -rf "$2"' _ "$REINDEX" "$HLOCK" \
  </dev/null >>"$HOOK_LOG" 2>&1 &
disown 2>/dev/null || true

echo "memory-search: заметки менялись — переиндексация в фоне"
exit 0
