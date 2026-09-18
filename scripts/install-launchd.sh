#!/usr/bin/env bash
# Install / remove / inspect the launchd agent that runs qmd-watch.sh from DATA/bin.
# Usage: install-launchd.sh --data <DIR> [--label L] [--dry-run|--remove|--status]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

DATA=""; LABEL="com.jadlis.memory-search.watch"; MODE="install"
while [ $# -gt 0 ]; do
  case "$1" in
    --data) DATA="${2:-}"; shift 2 ;;
    --data=*) DATA="${1#--data=}"; shift ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --label=*) LABEL="${1#--label=}"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --remove) MODE="remove"; shift ;;
    --status) MODE="status"; shift ;;
    -h|--help)
      echo "Использование: install-launchd.sh --data <DIR> [--label L] [--dry-run|--remove|--status]"
      exit 0 ;;
    *) echo "install-launchd: неизвестный аргумент: $1" >&2; exit 64 ;;
  esac
done
[ -n "$LABEL" ] || { echo "install-launchd: пустой --label" >&2; exit 64; }

if [ -n "$DATA" ]; then
  case "$DATA" in /*) ;; *) DATA="$PWD/$DATA" ;; esac
  export JMS_DATA="${DATA%/}"
fi
[ "$MODE" = "install" ] || export JMS_NO_MKDIR=1
. "$HERE/qmd-env.sh"
DATA="$JMS_DATA"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Автообновление через launchd есть только на macOS. На Linux добавьте в crontab (crontab -e) строку:"
  echo "@reboot JMS_DATA=$DATA nohup bash $DATA/bin/qmd-watch.sh >/dev/null 2>&1 &"
  echo "и один раз скопируйте скрипты: mkdir -p $DATA/bin && cp $ROOT/scripts/qmd-{env,reindex,watch}.sh $DATA/bin/"
  exit 2
fi

UIDN="$(id -u)"
AGENTS="$HOME/Library/LaunchAgents"
PLIST="$AGENTS/$LABEL.plist"
TARGET="gui/$UIDN/$LABEL"

agent_state() {
  launchctl print "$TARGET" 2>/dev/null | awk -F'= ' '/^[[:space:]]*state = / {print "state = " $2; exit}'
}

xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

render() {
  local qdir="" ndir="" p
  command -v qmd >/dev/null 2>&1 && qdir="$(dirname "$(command -v qmd)")"
  command -v node >/dev/null 2>&1 && ndir="$(dirname "$(command -v node)")"
  # Clean PATH: qmd-env defaults + qmd/node dirs + system dirs (not the caller's session PATH).
  p="$(env PATH="$qdir:$ndir" JMS_DATA="$DATA" JMS_NO_MKDIR=1 "${BASH:-/bin/bash}" -c '. "$1"; printf "%s" "$PATH"' _ "$HERE/qmd-env.sh")"
  p="$(printf '%s' "$p" | sed -e 's/^://' -e 's/::*/:/g')"
  [ -n "$p" ] || p="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  sed -e "s|@@LABEL@@|$(sed_escape "$(xml_escape "$LABEL")")|g" \
      -e "s|@@DATA@@|$(sed_escape "$(xml_escape "$DATA")")|g" \
      -e "s|@@PATH@@|$(sed_escape "$(xml_escape "$p")")|g" \
      "$HERE/launchd.plist.template"
}

case "$MODE" in
  dry-run)
    render
    exit 0 ;;

  remove)
    if [ ! -f "$PLIST" ]; then
      launchctl bootout "$TARGET" >/dev/null 2>&1 || true
      echo "Автообновление ($LABEL) не было установлено — удалять нечего."
      exit 0
    fi
    launchctl bootout "$TARGET" >/dev/null 2>&1 || true
    rm -f "$PLIST"
    echo "Автообновление выключено: агент $LABEL остановлен, $PLIST удалён. Индекс и логи в $DATA остались."
    exit 0 ;;

  status)
    if [ ! -f "$PLIST" ]; then
      echo "Автообновление не установлено ($PLIST нет)."
      exit 3
    fi
    st="$(agent_state)"
    echo "агент: $LABEL"
    echo "${st:-state = не загружен в launchd}"
    ALIVE="$JMS_STATE/watch.alive"
    if [ -f "$ALIVE" ]; then
      echo "watch.alive: $(( $(date +%s) - $(stat -f %m "$ALIVE") )) с назад"
    else
      echo "watch.alive: нет (poller ещё ни разу не отработал)"
    fi
    if [ -f "$JMS_LOGS/watch.log" ]; then
      echo "watch.log (последние 3 строки):"
      tail -n 3 "$JMS_LOGS/watch.log"
    fi
    exit 0 ;;
esac

# install
mkdir -p "$DATA/bin" "$DATA/logs" "$DATA/state" || exit 1
for f in qmd-env.sh qmd-reindex.sh qmd-watch.sh; do
  cp -f "$ROOT/scripts/$f" "$DATA/bin/$f" && chmod +x "$DATA/bin/$f" || {
    echo "Не удалось скопировать $f в $DATA/bin" >&2; exit 1; }
done

tmp="$(mktemp "${TMPDIR:-/tmp}/jms-plist.XXXXXX")" || exit 1
render > "$tmp"
if ! plutil -lint -s "$tmp" >/dev/null 2>&1; then
  echo "Сгенерированный plist не прошёл plutil -lint:" >&2
  plutil -lint "$tmp" >&2
  rm -f "$tmp"
  exit 1
fi
mkdir -p "$AGENTS"
mv -f "$tmp" "$PLIST"
chmod 644 "$PLIST"

launchctl bootout "$TARGET" >/dev/null 2>&1 || true
if ! err="$(launchctl bootstrap "gui/$UIDN" "$PLIST" 2>&1)"; then
  echo "launchctl bootstrap не сработал: $err" >&2
  echo "Диагностика: bash $HERE/install-launchd.sh --data $DATA --status" >&2
  exit 1
fi
sleep 1
echo "Автообновление включено: агент $LABEL следит за папками коллекций (опрос раз в минуту, полная сверка раз в час)."
echo "plist: $PLIST"
echo "$(agent_state || true)"
exit 0
