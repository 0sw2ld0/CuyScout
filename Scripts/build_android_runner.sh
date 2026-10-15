#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"${REPO_DIR}/Runner/AndroidRunner/gradlew" -p "${REPO_DIR}/Runner/AndroidRunner" :core:test :host:assembleDebug :host:assembleDebugAndroidTest :host:lintDebug :smokeapp:assembleDebug :smokeapp:lintDebug
