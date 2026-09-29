#!/usr/bin/env bash
# Instala Laya como servicio local compartido, fuera de cualquier proyecto:
#   ~/Library/Application Support/Laya/
#     venv/        entorno Python con laya[serve]
#     models/      caché de Hugging Face solo para Laya (HF_HOME)
#     logs/        salida del servicio
#     laya.env     configuración (puerto, modelos a precargar, dispositivo)
#     laya-service.sh  start | stop | status | restart
# Cualquier programa lo usa por HTTP: POST http://127.0.0.1:$LAYA_PORT/v1/systemone
# Idempotente: volver a correrlo actualiza el paquete sin tocar laya.env ni los modelos.
set -euo pipefail

LAYA_HOME="${LAYA_HOME:-$HOME/Library/Application Support/Laya}"
PYTHON="${PYTHON:-python3}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$LAYA_HOME/models" "$LAYA_HOME/logs"
if [[ ! -x "$LAYA_HOME/venv/bin/python" ]]; then
  echo "Creando entorno en $LAYA_HOME/venv ..."
  "$PYTHON" -m venv "$LAYA_HOME/venv"
fi
"$LAYA_HOME/venv/bin/python" -m pip install -q --upgrade pip
"$LAYA_HOME/venv/bin/python" -m pip install -q --upgrade "laya[serve]"

if [[ ! -f "$LAYA_HOME/laya.env" ]]; then
  cat > "$LAYA_HOME/laya.env" <<'EOF'
# Configuración del servicio Laya compartido. Solo escucha en esta Mac.
LAYA_HOST=127.0.0.1
LAYA_PORT=8791
# Checkpoints a cargar al arrancar (el resto se carga al primer uso): english, multilingual, typed-decisions
LAYA_MODELS=english
LAYA_PRELOAD=1
# Dispositivo torch: vacío = automático (MPS en Apple Silicon)
LAYA_DEVICE=
LAYA_LOG_LEVEL=warning
# Si se define, los clientes deben enviar Authorization: Bearer <clave>
LAYA_API_KEY=
EOF
fi
cp "$SRC_DIR/laya-service.sh" "$LAYA_HOME/laya-service.sh"
chmod +x "$LAYA_HOME/laya-service.sh"

echo "Laya $("$LAYA_HOME/venv/bin/python" -m pip show laya | awk '/^Version/{print $2}') instalado en: $LAYA_HOME"
echo "Arrancar: \"$LAYA_HOME/laya-service.sh\" start"
