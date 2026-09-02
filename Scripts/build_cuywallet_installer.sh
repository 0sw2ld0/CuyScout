#!/usr/bin/env bash
set -euo pipefail

# Genera el INSTALADOR de CuyWallet que consume CuyScout: un .app de simulador y
# su empaquetado .ipa (Payload/CuyWallet.app). CuyScout no necesita nada más:
# lee el bundle id del Info.plist, instala con simctl y conduce la app con su
# runner genérico, sin ver el código fuente.
#
# Uso:
#   Scripts/build_cuywallet_installer.sh [ruta-proyecto-CuyWallet]
#
# Un .ipa firmado para dispositivo físico requiere `xcodebuild archive` con un
# provisioning profile; CuyScout automatiza simuladores, así que el instalador
# útil aquí es el de simulador.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="${1:-${CUYWALLET_PROJECT:-$HOME/Documents/Agentes/CuyWallet}}"
PROJECT="$PROJECT_DIR/CuyWallet.xcodeproj"
DERIVED="$REPO/.build/cuywallet-build"
OUT="$REPO/.build/installers"
APP="$DERIVED/Build/Products/Release-iphonesimulator/CuyWallet.app"

[[ -d "$PROJECT" ]] || { echo "ERROR: no existe $PROJECT"; exit 1; }

echo "== Compilando CuyWallet (Release, iphonesimulator)"
xcodebuild build \
  -project "$PROJECT" \
  -scheme CuyWallet \
  -configuration Release \
  -sdk iphonesimulator \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3

[[ -d "$APP" ]] || { echo "ERROR: no se generó $APP"; exit 1; }

echo "== Empaquetando .ipa"
mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
rm -f "$OUT/CuyWallet.ipa"
(cd "$STAGE" && zip -qry "$OUT/CuyWallet.ipa" Payload)
rm -rf "$OUT/CuyWallet.app"
cp -R "$APP" "$OUT/CuyWallet.app"

BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
echo "== Instalador listo"
echo "   bundle id : $BUNDLE"
echo "   .app      : $OUT/CuyWallet.app"
echo "   .ipa      : $OUT/CuyWallet.ipa ($(du -h "$OUT/CuyWallet.ipa" | cut -f1))"
echo
echo "Úsalo con CuyScout mediante la capability appium:app, por ejemplo:"
echo "   curl -X POST http://127.0.0.1:4723/session -H 'Content-Type: application/json' \\"
echo "     -d '{\"capabilities\":{\"alwaysMatch\":{\"appium:app\":\"$OUT/CuyWallet.ipa\",\"appium:automationName\":\"XCUITest\"}}}'"
