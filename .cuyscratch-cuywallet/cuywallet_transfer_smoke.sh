#!/usr/bin/env bash
set -euo pipefail

# Transferencia entre cuentas propias de CuyWallet conducida por CuyScout vía W3C/WebDriver.
# Requiere: proyecto CuyWallet con el target CuyWalletUITests (ScoutBridgeRunner) construido
# para el simulador destino y el binario cuyscout disponible.

CUYSCOUT_URL="${CUYSCOUT_URL:-http://127.0.0.1:4799}"
CUYSCOUT_PORT="${CUYSCOUT_PORT:-4799}"
CUYSCOUT_BIN="${CUYSCOUT_BIN:-$HOME/Documents/cuycoders/workspace/CuyCards/CuyScout/.build/debug/cuyscout}"
CUYWALLET_PROJECT="${CUYWALLET_PROJECT:-$HOME/Documents/Agentes/CuyWallet}"
DERIVED_DATA="$CUYWALLET_PROJECT/build/cuyscout-dd"
BUNDLE_ID="com.cuywallet.app"
EMAIL="${CUYWALLET_EMAIL:-demo@cuywallet.com}"
PASSWORD="${CUYWALLET_PASSWORD:-Cuywallet2024}"
AMOUNT="${CUYWALLET_AMOUNT:-100}"

if [[ -z "${CUYSCOUT_DEVICE_ID:-}" ]]; then
  CUYSCOUT_DEVICE_ID="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin); ds=[x for g in d["devices"].values() for x in g if x.get("isAvailable")]; print(ds[0]["udid"])')"
fi
echo "== Simulador: $CUYSCOUT_DEVICE_ID"

XCODEBUILD_PID=""
SESSION_ID=""
SERVER_PID=""
cleanup() {
  touch /tmp/cuyscout-bridge-stop 2>/dev/null || true
  if [[ -n "$XCODEBUILD_PID" ]] && kill -0 "$XCODEBUILD_PID" 2>/dev/null; then
    for _ in $(seq 1 30); do kill -0 "$XCODEBUILD_PID" 2>/dev/null || break; sleep 1; done
    kill "$XCODEBUILD_PID" 2>/dev/null || true
  fi
  if [[ -n "$SESSION_ID" ]]; then curl -fsS -X DELETE "$CUYSCOUT_URL/session/$SESSION_ID" >/dev/null 2>&1 || true; fi
  if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi
  rm -f /tmp/cuyscout-bridge-stop /tmp/cuyscout-bridge.json
}
trap cleanup EXIT

if ! curl -fsS --max-time 2 "$CUYSCOUT_URL/status" >/dev/null 2>&1; then
  "$CUYSCOUT_BIN" "$CUYSCOUT_PORT" > /tmp/cuyscout-cuywallet.log 2>&1 &
  SERVER_PID=$!
fi
for _ in $(seq 1 30); do curl -fsS "$CUYSCOUT_URL/status" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "$CUYSCOUT_URL/status" >/dev/null

SESSION_JSON="$(curl -fsS -X POST "$CUYSCOUT_URL/session" -H 'Content-Type: application/json' \
  -d "{\"capabilities\":{\"alwaysMatch\":{\"platformName\":\"iOS\",\"appium:udid\":\"$CUYSCOUT_DEVICE_ID\",\"appium:automationName\":\"XCUITest\",\"appium:bundleId\":\"$BUNDLE_ID\"}}}")"
SESSION_ID="$(printf '%s' "$SESSION_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"]["sessionId"])')"
echo "== Sesión CuyScout: $SESSION_ID"
curl -fsS -X POST "$CUYSCOUT_URL/session/$SESSION_ID/timeouts" -H 'Content-Type: application/json' -d '{"implicit":15000}' >/dev/null

cat > /tmp/cuyscout-bridge.json <<EOF
{"url": "$CUYSCOUT_URL", "sessionId": "$SESSION_ID", "bundleId": "$BUNDLE_ID", "maxSeconds": 480}
EOF
rm -f /tmp/cuyscout-bridge-stop

if ls "$DERIVED_DATA"/Build/Products/*.xctestrun >/dev/null 2>&1; then XCODEBUILD_ACTION="test-without-building"; else XCODEBUILD_ACTION="test"; fi
echo "== xcodebuild $XCODEBUILD_ACTION (runner XCTest del puente)"
xcodebuild "$XCODEBUILD_ACTION" -project "$CUYWALLET_PROJECT/CuyWallet.xcodeproj" -scheme CuyWallet \
  -destination "platform=iOS Simulator,id=$CUYSCOUT_DEVICE_ID" -derivedDataPath "$DERIVED_DATA" \
  > /tmp/cuywallet-xcodebuild.log 2>&1 &
XCODEBUILD_PID=$!

for _ in $(seq 1 60); do
  STATUS="$(curl -fsS "$CUYSCOUT_URL/session/$SESSION_ID/bridge/status" 2>/dev/null || true)"
  if printf '%s' "$STATUS" | grep -q '"registered":true'; then break; fi
  sleep 1
done
printf '%s' "$STATUS" | grep -q '"registered":true' || { echo "El puente XCTest no se registró"; tail -30 /tmp/cuywallet-xcodebuild.log; exit 1; }
echo "== Puente XCTest registrado"

element_id() {
  curl -fsS -X POST "$CUYSCOUT_URL/session/$SESSION_ID/element" -H 'Content-Type: application/json' \
    -d "{\"using\":\"accessibility id\",\"value\":\"$1\"}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"]["element-6066-11e4-a52e-4f735466cecf"])'
}
send_keys() { curl -fsS -X POST "$CUYSCOUT_URL/element/$1/value" -H 'Content-Type: application/json' -d "{\"text\":\"$2\"}" >/dev/null; }
click() { curl -fsS -X POST "$CUYSCOUT_URL/element/$1/click" >/dev/null; }
element_text() { curl -fsS "$CUYSCOUT_URL/element/$1/text" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])'; }
fail_with_login_error() {
  ERROR_TEXT="$(curl -fsS "$CUYSCOUT_URL/session/$SESSION_ID/element" -X POST -H 'Content-Type: application/json' -d '{"using":"accessibility id","value":"label_login_error"}' >/dev/null 2>&1 && curl -fsS "$CUYSCOUT_URL/element/$(element_id label_login_error)/text" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])' || echo 'no disponible')"
  echo "ERROR: $1 (login_error: $ERROR_TEXT)"; exit 1
}

echo "== Login"
send_keys "$(element_id input_email)" "$EMAIL"
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

SUMMARY_FROM="$(element_text "$(element_id label_summary_from)")"
SUMMARY_TO="$(element_text "$(element_id label_summary_to)")"
echo "== Resumen: $SUMMARY_FROM | $SUMMARY_TO"

send_keys "$(element_id input_amount)" "$AMOUNT"
send_keys "$(element_id input_memo)" "Transferencia entre cuentas propias via CuyScout"
SUMMARY_AMOUNT="$(element_text "$(element_id label_summary_amount)")"
echo "== $SUMMARY_AMOUNT"

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
RESULT_FROM="$(element_text "$(element_id label_confirm_from)")"
RESULT_TO="$(element_text "$(element_id label_confirm_to)")"
RESULT_DATETIME="$(element_text "$(element_id label_result_datetime)")"
RESULT_MEMO="$(element_text "$(element_id label_confirm_memo)")"
echo "== Resultado: $RESULT_TITLE | $OPERATION | $RESULT_AMOUNT | $RESULT_FROM | $RESULT_TO | $RESULT_DATETIME | $RESULT_MEMO"

[[ "$RESULT_TITLE" == "¡Transferencia exitosa!" ]] || { echo "ERROR: título de resultado inesperado"; exit 1; }
printf '%s' "$RESULT_AMOUNT" | grep -q "$(printf 'S/ %.2f' "$AMOUNT")" || { echo "ERROR: monto del resultado inesperado"; exit 1; }
printf '%s' "$OPERATION" | grep -qE 'OP[0-9]{6}' || { echo "ERROR: número de operación ausente"; exit 1; }

curl -fsS "$CUYSCOUT_URL/session/$SESSION_ID/screenshot/raw" -o /tmp/cuywallet-transfer-result.png
echo "== Captura: /tmp/cuywallet-transfer-result.png"

touch /tmp/cuyscout-bridge-stop
for _ in $(seq 1 60); do kill -0 "$XCODEBUILD_PID" 2>/dev/null || break; sleep 1; done
if kill -0 "$XCODEBUILD_PID" 2>/dev/null; then kill "$XCODEBUILD_PID" 2>/dev/null; tail -20 /tmp/cuywallet-xcodebuild.log; echo "ERROR: xcodebuild no terminó"; exit 1; fi
grep -q "Test Suite 'ScoutBridgeUITests.xctest' passed\|TEST SUCCEEDED" /tmp/cuywallet-xcodebuild.log || { tail -30 /tmp/cuywallet-xcodebuild.log; echo "ERROR: la suite del runner no pasó"; exit 1; }

echo "== Transferencia de S/ $AMOUNT entre cuentas propias: OK (sesión $SESSION_ID)"