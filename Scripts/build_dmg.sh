#!/usr/bin/env bash
# Empaqueta CuyScout.app en un .dmg firmado con Developer ID y, si hay credenciales,
# lo notariza y le grapa el ticket para que Gatekeeper lo abra sin avisos.
#
# Uso: Scripts/build_dmg.sh
# Variables:
#   CUYSCOUT_SIGN_IDENTITY   identidad de firma; por defecto, el primer "Developer ID Application"
#   CUYSCOUT_NOTARY_PROFILE  perfil de `xcrun notarytool store-credentials` (omítelo para no notarizar)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${REPO_DIR}/dist"
APP_DIR="${REPO_DIR}/.build/CuyScout.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${REPO_DIR}/Scripts/CuyScout-Info.plist")"
DMG="${DIST_DIR}/CuyScout-${VERSION}.dmg"

IDENTITY="${CUYSCOUT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"
[[ -n "${IDENTITY}" ]] || { echo "No hay una identidad 'Developer ID Application' en el llavero." >&2; exit 1; }
echo "Firmando con: ${IDENTITY}"

rm -rf "${APP_DIR}"
CUYSCOUT_SIGN_IDENTITY="${IDENTITY}" "${REPO_DIR}/Scripts/build_cuyscout_app.sh" "${APP_DIR}"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
cp -Rp "${APP_DIR}" "${STAGE}/CuyScout.app"
ln -s /Applications "${STAGE}/Applications"
mkdir -p "${DIST_DIR}"
rm -f "${DMG}"
hdiutil create -volname "CuyScout" -srcfolder "${STAGE}" -fs HFS+ -format UDZO -ov "${DMG}" >/dev/null
codesign --force --timestamp --sign "${IDENTITY}" "${DMG}"
echo "DMG firmado: ${DMG}"

if [[ -n "${CUYSCOUT_NOTARY_PROFILE:-}" ]]; then
  echo "Notarizando (suele tardar unos minutos) ..."
  xcrun notarytool submit "${DMG}" --keychain-profile "${CUYSCOUT_NOTARY_PROFILE}" --wait
  xcrun stapler staple "${DMG}"
  xcrun stapler validate "${DMG}"
  spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"
  echo "DMG notarizado y listo para distribuir: ${DMG}"
else
  echo "Aviso: sin CUYSCOUT_NOTARY_PROFILE el DMG está firmado pero NO notarizado; en otras Macs Gatekeeper lo bloqueará." >&2
fi
