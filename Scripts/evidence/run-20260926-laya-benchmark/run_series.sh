#!/usr/bin/env bash
# Serie alternada LLM / LLM+Laya sobre el mismo escenario y simulador dedicado.
# Reinicia el simulador antes de cada corrida para partir con un runner XCTest limpio.
set -uo pipefail

PY="${PY:?ruta al python del venv con laya}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UDID="${UDID:?udid del simulador dedicado}"
APP="${APP:?ruta al .app}"
FEATURE="${FEATURE:?ruta al .feature}"
FIXTURES="${FIXTURES:?ruta a credentials.test.json}"
RUNS="${RUNS:-3}"
THRESHOLD="${THRESHOLD:-0.35}"
MODES="${MODES:-llm laya}"
TAG="${TAG:-serie}"
EXTRA="${EXTRA:-}"

for n in $(seq 1 "$RUNS"); do
  for mode in $MODES; do
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1
    xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" -b >/dev/null
    out="$DIR/results/$TAG-$mode-$n.json"
    echo "=== $mode #$n ==="
    "$PY" "$DIR/bench_laya.py" --mode "$mode" --threshold "$THRESHOLD" --feature "$FEATURE" --fixtures "$FIXTURES" \
      --app "$APP" --udid "$UDID" --out "$out" $EXTRA 2>&1 | grep -v -iE "warn|Fetching|agent = Agent" | tail -1 | cut -c1-400
  done
done
