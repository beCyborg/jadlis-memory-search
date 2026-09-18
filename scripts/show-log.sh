#!/usr/bin/env bash
# Print the tail of one plugin log without the caller reading files outside the project.
# Usage: show-log.sh <setup-build|reindex|watch|hook|launchd> [lines]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
export JMS_NO_MKDIR=1
. "$HERE/qmd-env.sh"
name="${1:-reindex}"; n="${2:-10}"
case "$name" in setup-build|reindex|watch|hook|launchd) ;; *) echo "show-log: неизвестный лог: $name" >&2; exit 64 ;; esac
case "$n" in ''|*[!0-9]*) n=10 ;; esac
f="$JMS_LOGS/$name.log"
[ -f "$f" ] || { echo "лога ещё нет: $f"; exit 0; }
tail -n "$n" "$f"
