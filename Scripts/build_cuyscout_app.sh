#!/usr/bin/env bash
# Construye CuyScout.app con la interfaz SwiftUI y el gateway de terminal.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-${REPO_DIR}/.build/CuyScout.app}"

cd "${REPO_DIR}"
swift build -c release --product cuyscout
swift build -c release --product cuyscout-app
swift build -c release --product cuyscout-mcp

BIN_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"
ICONSET_DIR="${REPO_DIR}/.build/CuyScout.iconset"
ICON_SOURCE="${REPO_DIR}/Assets/Brand/CuyScoutIcon-master.png"
mkdir -p "${BIN_DIR}" "${RES_DIR}/Brand" "${ICONSET_DIR}"
cp "${REPO_DIR}/.build/release/cuyscout" "${BIN_DIR}/cuyscout"
cp "${REPO_DIR}/.build/release/cuyscout-app" "${BIN_DIR}/cuyscout-app"
cp "${REPO_DIR}/.build/release/cuyscout-mcp" "${BIN_DIR}/cuyscout-mcp"
cp "${REPO_DIR}/Scripts/CuyScout-Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${ICON_SOURCE}" "${RES_DIR}/Brand/CuyScoutIcon-master.png"
mkdir -p "${RES_DIR}/Runner"
cp -R "${REPO_DIR}/Runner/ScoutRunner" "${RES_DIR}/Runner/"

# iconutil requiere el conjunto de tamaños estándar de macOS.
for size in 16 32 128 256 512; do
  sips -s format png -z "${size}" "${size}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -s format png -z "${doubled}" "${doubled}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET_DIR}" -o "${RES_DIR}/CuyScout.icns"
chmod 755 "${BIN_DIR}/cuyscout" "${BIN_DIR}/cuyscout-app" "${BIN_DIR}/cuyscout-mcp"
codesign --force --deep --sign - "${APP_DIR}"

echo "App lista: ${APP_DIR}"
