#!/usr/bin/env bash
# Controla el servicio Laya compartido: start | stop | status | restart
# Lee la configuración de laya.env junto a este script (o de $LAYA_HOME).
set -uo pipefail

LAYA_HOME="${LAYA_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
set -a; source "$LAYA_HOME/laya.env"; set +a
export HF_HOME="$LAYA_HOME/models"
[[ -z "${LAYA_DEVICE:-}" ]] && unset LAYA_DEVICE
[[ -z "${LAYA_API_KEY:-}" ]] && unset LAYA_API_KEY
URL="http://${LAYA_HOST}:${LAYA_PORT}"
PID_FILE="$LAYA_HOME/laya.pid"

is_up() { curl -sf -m 2 "$URL/health" >/dev/null 2>&1; }

case "${1:-status}" in
  start)
    if is_up; then echo "Laya ya está arriba en $URL"; exit 0; fi
    nohup "$LAYA_HOME/venv/bin/laya-serve" >> "$LAYA_HOME/logs/laya.log" 2>&1 &
    echo $! > "$PID_FILE"
    echo "Arrancando Laya en $URL (la primera vez descarga los modelos) ..."
    for _ in $(seq 1 300); do
      is_up && { echo "Laya listo en $URL"; exit 0; }
      kill -0 "$(cat "$PID_FILE")" 2>/dev/null || { echo "Laya terminó al arrancar; revisa $LAYA_HOME/logs/laya.log" >&2; exit 1; }
      sleep 2
    done
    echo "Laya no respondió a tiempo; revisa $LAYA_HOME/logs/laya.log" >&2; exit 1 ;;
  stop)
    [[ -f "$PID_FILE" ]] && kill "$(cat "$PID_FILE")" 2>/dev/null && rm -f "$PID_FILE" && echo "Laya detenido" || echo "Laya no estaba corriendo" ;;
  restart) "$0" stop; sleep 1; "$0" start ;;
  status)
    if is_up; then echo "arriba: $URL"; curl -s "$URL/health"; echo; else echo "abajo: $URL"; exit 1; fi ;;
  *) echo "uso: $0 start|stop|status|restart" >&2; exit 2 ;;
esac
