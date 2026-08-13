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

SESSION_JSON="$(request -X POST "${BASE_URL}${BASE_PATH}/session" -H 'Content-Type: application/json' -d "{\"capabilities\":{\"alwaysMatch\":{\"platformName\":\"iOS\",\"appium:udid\":\"${DEVICE_ID}\",\"appium:automationName\":\"XCUITest\"}}}")"
SESSION_ID="$(printf '%s' "${SESSION_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"]["sessionId"])')"
CAPABILITIES="$(request "${BASE_URL}${BASE_PATH}/session/${SESSION_ID}/capabilities")"
printf '%s' "${CAPABILITIES}" | grep -q 'appium:driverId'

request -X POST "${BASE_URL}${BASE_PATH}/session/${SESSION_ID}/timeouts" -H 'Content-Type: application/json' -d '{"implicit":1000,"pageLoad":1000,"script":1000}' | grep -q 'null'
request "${BASE_URL}${BASE_PATH}/session/${SESSION_ID}/timeouts" | grep -q 'implicit'
request -X DELETE "${BASE_URL}${BASE_PATH}/session/${SESSION_ID}" >/dev/null
echo "CuyScout W3C smoke: OK (${SESSION_ID})"
