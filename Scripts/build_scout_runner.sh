#!/usr/bin/env bash
set -euo pipefail

# Compila una sola vez el runner genérico de CuyScout (Runner/ScoutRunner).
# Produce un .xctestrun reutilizable que el gateway lanza con
# `xcodebuild test-without-building` para conducir cualquier app instalada,
# sin necesidad del código fuente de la app bajo prueba.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$REPO/.build/scout-runner-dd"

# Xcode 26 no resuelve el product type ui-testing con destination genérico:
# se necesita un simulador concreto (usa el primero booted si no se define SCOUT_RUNNER_DESTINATION).
if [[ -z "${SCOUT_RUNNER_DESTINATION:-}" ]]; then
  UDID="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin); ds=[x for g in d["devices"].values() for x in g if x.get("isAvailable")]; print(ds[0]["udid"] if ds else "")')"
  [[ -n "$UDID" ]] || { echo "ERROR: no hay simulador booted; arranca uno o define SCOUT_RUNNER_DESTINATION"; exit 1; }
  SCOUT_RUNNER_DESTINATION="platform=iOS Simulator,id=$UDID"
fi

xcodebuild build-for-testing \
  -project "$REPO/Runner/ScoutRunner/ScoutRunner.xcodeproj" \
  -scheme ScoutRunner \
  -destination "$SCOUT_RUNNER_DESTINATION" \
  -derivedDataPath "$DERIVED" 2>&1 | tail -5

echo "== Runner prebuilt:"
ls "$DERIVED"/Build/Products/*.xctestrun