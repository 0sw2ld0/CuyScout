#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${CUYSCOUT_URL:-http://127.0.0.1:4723}"
BASE_PATH="${CUYSCOUT_BASE_PATH:-}"
DEVICE_ID="${CUYSCOUT_DEVICE_ID:?Define CUYSCOUT_DEVICE_ID con un simulador disponible}"
AUTH_HEADER=()
if [[ -n "${CUYSCOUT_TOKEN:-}" ]]; then AUTH_HEADER=(-H "Authorization: Bearer ${CUYSCOUT_TOKEN}"); fi

request() { curl -fsS "${AUTH_HEADER[@]}" "$@"; }
request "${BASE_URL}${BASE_PATH}/status" | grep -q 'CuyScout'
request "${BASE_URL}${BASE_PATH}/conformance" | grep -q 'W3C WebDriver'

WORKER_JSON="$(request -X POST "${BASE_URL}${BASE_PATH}/workers" -H 'Content-Type: application/json' -d '{"url":"http://127.0.0.1:4724","capabilities":["smoke"],"maxSessions":2}')"
WORKER_ID="$(printf '%s' "${WORKER_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
request "${BASE_URL}${BASE_PATH}/workers" | grep -q "${WORKER_ID}"
request -X POST "${BASE_URL}${BASE_PATH}/workers/${WORKER_ID}/heartbeat" -H 'Content-Type: application/json' -d '{"activeSessions":1}' | grep -q 'online'
request "${BASE_URL}${BASE_PATH}/dashboard" | grep -q 'workersOnline'
request -X DELETE "${BASE_URL}${BASE_PATH}/workers/${WORKER_ID}" | grep -q 'removed'

SESSION_JSON="$(request -X POST "${BASE_URL}${BASE_PATH}/session" -H 'Content-Type: application/json' -d "{\"capabilities\":{\"alwaysMatch\":{\"platformName\":\"iOS\",\"appium:udid\":\"${DEVICE_ID}\",\"appium:automationName\":\"XCUITest\"}}}")"
SESSION_ID="$(printf '%s' "${SESSION_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"]["sessionId"])')"
CAPABILITIES="$(request "${BASE_URL}${BASE_PATH}/session/${SESSION_ID}/capabilities")"
printf '%s' "${CAPABILITIES}" | grep -q 'appium:driverId'

request -X POST "${BASE_URL}${BASE_PATH}/session/${SESSION_ID}/timeouts" -H 'Content-Type: application/json' -d '{"implicit":1000,"pageLoad":1000,"script":1000}' | grep -q 'null'
request "${BASE_URL}${BASE_PATH}/session/${SESSION_ID}/timeouts" | grep -q 'implicit'

# Handshake WebSocket BiDi: el 101 y el Sec-WebSocket-Accept esperado (vector RFC 6455).
# curl trata el 101 como respuesta interina y espera hasta --max-time; los headers
# ya están volcados, por eso se tolera el código de salida y se validan con grep.
WS_HEADERS="$(curl -sS --max-time 2 -o /dev/null -D - "${AUTH_HEADER[@]}" \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Version: 13' \
  "${BASE_URL}${BASE_PATH}/session/${SESSION_ID}/events/websocket?maxDuration=1&after=0" || true)"
printf '%s' "${WS_HEADERS}" | grep -q '101 Switching Protocols'
printf '%s' "${WS_HEADERS}" | grep -q 'Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo='

request -X DELETE "${BASE_URL}${BASE_PATH}/session/${SESSION_ID}" >/dev/null
echo "CuyScout W3C smoke: OK (${SESSION_ID})"
