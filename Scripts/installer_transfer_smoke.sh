#!/usr/bin/env bash
set -euo pipefail

# DEMO "solo con el instalador": prueba una app iOS sin su código fuente.
# Envía POST /session con la capability `appium:app` apuntando al .app; el gateway
# CuyScout lo instala con simctl, resuelve el bundle ID del Info.plist, lanza su
# runner genérico prebuilt (Runner/ScoutRunner) y conduce el flujo completo por
# W3C/WebDriver: login → transferencia de cuentas propias → confirmación → resultado.
#
# Requisitos: Scripts/build_scout_runner.sh ejecutado una vez (runner prebuilt) y
# un simulador booted. La app bajo prueba solo se necesita como instalador (.app).

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CUYSCOUT_URL="${CUYSCOUT_URL:-http://127.0.0.1:4799}"
CUYSCOUT_PORT="${CUYSCOUT_PORT:-4799}"
CUYSCOUT_BIN="${CUYSCOUT_BIN:-$REPO/.build/debug/cuyscout}"
INSTALLER="${CUYWALLET_INSTALLER:-$REPO/.build/cuywallet-build/Release-iphonesimulator/CuyWallet.app}"
EMAIL="${CUYWALLET_EMAIL:-demo@cuywallet.com}"
PASSWORD="${CUYWALLET_PASSWORD:-Cuywallet2024}"
AMOUNT="${CUYWALLET_AMOUNT:-100}"

[[ -d "$INSTALLER" ]] || { echo "ERROR: no existe el instalador $INSTALLER"; exit 1; }
[[ -n "${CUYSCOUT_DEVICE_ID:-}" ]] && DEVICE_CAP="\"appium:udid\":\"$CUYSCOUT_DEVICE_ID\"," || DEVICE_CAP=""

SESSION_ID=""
SERVER_PID=""
cleanup() {
  if [[ -n "$SESSION_ID" ]]; then curl -fsS -X DELETE "$CUYSCOUT_URL/session/$SESSION_ID" >/dev/null 2>&1 || true; fi
  if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi
  rm -f /tmp/cuyscout-bridge-stop /tmp/cuyscout-bridge.json
}
trap cleanup EXIT

if ! curl -fsS --max-time 2 "$CUYSCOUT_URL/status" >/dev/null 2>&1; then
  "$CUYSCOUT_BIN" "$CUYSCOUT_PORT" > /tmp/cuyscout-installer-demo.log 2>&1 &
  SERVER_PID=$!
fi
for _ in $(seq 1 30); do curl -fsS "$CUYSCOUT_URL/status" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "$CUYSCOUT_URL/status" >/dev/null

echo "== Sesión solo-instalador: $(basename "$INSTALLER")"
SESSION_JSON="$(curl -fsS -X POST "$CUYSCOUT_URL/session" -H 'Content-Type: application/json' -d "{\"capabilities\":{\"alwaysMatch\":{${DEVICE_CAP}\"appium:app\":\"$INSTALLER\",\"appium:automationName\":\"XCUITest\"}}}")"
SESSION_ID="$(printf '%s' "$SESSION_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"]["sessionId"])')"
printf '%s' "$SESSION_JSON" | python3 -c 'import json,sys; c=json.load(sys.stdin)["value"]["capabilities"]; print("== Instalada: %s en %s (%s...)" % (c["appium:bundleId"], c["appium:deviceName"], c["appium:udid"][:8]))'
curl -fsS -X POST "$CUYSCOUT_URL/session/$SESSION_ID/timeouts" -H 'Content-Type: application/json' -d '{"implicit":15000}' >/dev/null

element_id() {
  curl -fsS -X POST "$CUYSCOUT_URL/session/$SESSION_ID/element" -H 'Content-Type: application/json' \
    -d "{\"using\":\"accessibility id\",\"value\":\"$1\"}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"]["element-6066-11e4-a52e-4f735466cecf"])'
}
# La sesión responde en cuanto el gateway crea el puente, pero el runner tarda en
# arrancar (xcodebuild test-without-building); el primer findElement que responde
# prueba que app instalada + runner + puente están vivos.
wait_element() {
  local id=""
  for _ in $(seq 1 10); do
    if id="$(element_id "$1" 2>/dev/null)"; then printf '%s' "$id"; return 0; fi
    sleep 2
  done
  return 1
}
send_keys() { curl -fsS -X POST "$CUYSCOUT_URL/session/$SESSION_ID/element/$1/value" -H 'Content-Type: application/json' -d "{\"text\":\"$2\"}" >/dev/null; }
click() { curl -fsS -X POST "$CUYSCOUT_URL/session/$SESSION_ID/element/$1/click" >/dev/null; }
element_text() { curl -fsS "$CUYSCOUT_URL/session/$SESSION_ID/element/$1/text" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])'; }
fail_with_login_error() {
  ERROR_TEXT="$(element_id label_login_error 2>/dev/null | head -1 | xargs -I{} element_text {} 2>/dev/null || echo 'no disponible')"
  echo "ERROR: $1 (login_error: $ERROR_TEXT)"; exit 1
}

echo "== Login"
EMAIL_ID="$(wait_element input_email)" || { echo "ERROR: el runner no respondió (revisa /tmp/cuyscout-installer-demo.log y que el simulador esté booted)"; exit 1; }
echo "== Pipeline vivo: app instalada desde el instalador + runner genérico respondiendo"
send_keys "$EMAIL_ID" "$EMAIL"
send_keys "$(element_id input_password)" "$PASSWORD"
click "$(element_id btn_login)"

GREETING=""
for _ in $(seq 1 6); do
  if GREETING_ID="$(element_id label_greeting 2>/dev/null)"; then GREETING="$(element_text "$GREETING_ID")"; break; fi
  sleep 2
done
[[ -n "$GREETING" ]] || fail_with_login_error "No apareció la pantalla de inicio tras el login"
echo "== Login OK: $GREETING"

echo "== Navegación a Transferir"
click "$(element_id btn_quick_transfer)"
echo "== Pantalla: $(element_text "$(element_id label_transfer_title)")"

echo "== Resumen: $(element_text "$(element_id label_summary_from)") | $(element_text "$(element_id label_summary_to)")"

send_keys "$(element_id input_amount)" "$AMOUNT"
send_keys "$(element_id input_memo)" "Transferencia entre cuentas propias via CuyScout (solo instalador)"
echo "== $(element_text "$(element_id label_summary_amount)")"

click "$(element_id btn_transfer_continue)"

CONFIRM_TITLE="$(element_text "$(element_id label_confirm_title)")"
CONFIRM_FROM="$(element_text "$(element_id label_confirm_from)")"
CONFIRM_TO="$(element_text "$(element_id label_confirm_to)")"
CONFIRM_AMOUNT="$(element_text "$(element_id label_confirm_amount)")"
echo "== Confirmación: $CONFIRM_TITLE | $CONFIRM_FROM | $CONFIRM_TO | $CONFIRM_AMOUNT"
printf '%s' "$CONFIRM_FROM" | grep -q "Cuenta Corriente \*\*\*\*1234" || { echo "ERROR: cuenta de origen inesperada"; exit 1; }
printf '%s' "$CONFIRM_TO" | grep -q "Wallet Digital CUY" || { echo "ERROR: cuenta de destino inesperada"; exit 1; }
printf '%s' "$CONFIRM_AMOUNT" | grep -q "S/ $AMOUNT" || { echo "ERROR: monto de confirmación inesperado"; exit 1; }

click "$(element_id btn_confirm_transfer)"

RESULT_TITLE="$(element_text "$(element_id label_result_title)")"
RESULT_AMOUNT="$(element_text "$(element_id label_result_amount)")"
OPERATION="$(element_text "$(element_id label_result_operation_number)")"
RESULT_FROM="$CONFIRM_FROM"
RESULT_TO="$CONFIRM_TO"
echo "== Resultado: $RESULT_TITLE | $OPERATION | $RESULT_AMOUNT | $RESULT_FROM | $RESULT_TO"

[[ "$RESULT_TITLE" == "¡Transferencia exitosa!" ]] || { echo "ERROR: título de resultado inesperado"; exit 1; }
printf '%s' "$RESULT_AMOUNT" | grep -q "$(printf 'S/ %.2f' "$AMOUNT")" || { echo "ERROR: monto del resultado inesperado"; exit 1; }
printf '%s' "$OPERATION" | grep -qE 'OP[0-9]{6}' || { echo "ERROR: número de operación ausente"; exit 1; }

curl -fsS "$CUYSCOUT_URL/session/$SESSION_ID/screenshot/raw" -o /tmp/cuywallet-transfer-result.png
echo "== Captura: /tmp/cuywallet-transfer-result.png"

echo "== Transferencia de S/ $AMOUNT entre cuentas propias SOLO CON EL INSTALADOR: OK (sesión $SESSION_ID)"