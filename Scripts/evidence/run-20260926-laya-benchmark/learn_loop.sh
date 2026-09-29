#!/usr/bin/env bash
# Prueba de aprendizaje: cada prueba parte con memoria vacía (CUYSCOUT_LESSONS_FILE nuevo) y tiene
# hasta ATTEMPTS intentos. Si un intento falla según el oráculo, bench_laya.py registra una lección
# candidata; el siguiente intento la lee de CuyScout y la aplica. Si acierta con ella, la refuerza.
set -uo pipefail

PY="${PY:?python del venv con laya}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
UDID="${UDID:?udid}"; APP="${APP:?app}"; FEATURE="${FEATURE:?feature}"; FIXTURES="${FIXTURES:?fixtures}"
MODES="${MODES:-llm laya2}"; TRIALS="${TRIALS:-3}"; ATTEMPTS="${ATTEMPTS:-3}"
OUT="$DIR/results/learn"; mkdir -p "$OUT"

ORACLE=(--oracle "Transferencia exitosa=>la transferencia no terminó con éxito"
        --oracle "Operación: OP=>no se obtuvo número de operación"
        --oracle "S/ 100.00=>el monto transferido no es S/ 100.00"
        --oracle "Desde: Wallet Digital CUY=>la cuenta de origen no es la que pide el escenario («cuywaller»)")

for mode in $MODES; do
  for t in $(seq 1 "$TRIALS"); do
    lessons="$OUT/$mode-t$t-lessons.json"; rm -f "$lessons"
    pkill -f ".build/debug/cuyscout 4723" 2>/dev/null; sleep 1
    (cd "$REPO" && CUYSCOUT_LESSONS_FILE="$lessons" nohup .build/debug/cuyscout 4723 > "$OUT/$mode-t$t-gateway.log" 2>&1 &)
    until curl -sf -m 2 http://127.0.0.1:4723/status >/dev/null; do sleep 1; done
    for n in $(seq 1 "$ATTEMPTS"); do
      xcrun simctl shutdown "$UDID" >/dev/null 2>&1
      xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" -b >/dev/null
      out="$OUT/$mode-t$t-a$n.json"
      echo "=== $mode prueba $t intento $n ==="
      "$PY" "$DIR/bench_laya.py" --mode "$mode" --threshold 0.35 --feature "$FEATURE" --fixtures "$FIXTURES" \
        --app "$APP" --udid "$UDID" --out "$out" --lessons --learn "${ORACLE[@]}" 2>&1 | grep -v -iE "warn|Fetching|agent = Agent" | tail -1 | cut -c1-220
      ok=$(python3 -c "import json;print(json.load(open('$out')).get('oracle_ok'))" 2>/dev/null)
      [ "$ok" = "True" ] && break
    done
  done
done
pkill -f ".build/debug/cuyscout 4723" 2>/dev/null
xcrun simctl shutdown "$UDID" >/dev/null 2>&1
echo "fin"
