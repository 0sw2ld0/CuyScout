#!/usr/bin/env bash
# Wrapper de `cuyscout init` que se puede correr desde CUALQUIER directorio.
# Resuelve la ubicación de este repo por sí mismo (no hace falta `cd` antes),
# convierte el destino a ruta absoluta y usa este repo como --cuyscout-repo
# por defecto (para que los scripts generados sepan dónde levantar el gateway).
#
# Uso:
#   Scripts/cuyscout_init.sh <directorio-destino> --app-path <ruta/a/MiApp.app> \
#     [--app-name MiApp] [--port 4723] [--vscode]
#
# Solo genera/actualiza scripts/, fixtures/credentials.test.json (si falta) y
# AGENTS.md. Nunca toca features/: ahí van los .feature que tú escribas.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 1 || "$1" == --* ]]; then
  echo "Uso: $0 <directorio-destino> --app-path <ruta/a/MiApp.app> [--app-name X] [--port 4723] [--vscode]" >&2
  exit 1
fi

TARGET_DIR="$1"; shift
mkdir -p "${TARGET_DIR}"
TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"

# Resuelve --app-path a ruta absoluta si vino relativa, sin tocar los demás flags.
ARGS=()
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--app-path" ]]; then
    ARGS+=("$1"); shift
    APP_PATH="$1"
    [[ "${APP_PATH}" != /* ]] && APP_PATH="$(cd "$(dirname "${APP_PATH}")" && pwd)/$(basename "${APP_PATH}")"
    ARGS+=("${APP_PATH}"); shift
  else
    ARGS+=("$1"); shift
  fi
done

if [[ ! " ${ARGS[*]} " == *" --cuyscout-repo "* ]]; then
  ARGS+=(--cuyscout-repo "${REPO_DIR}")
fi

echo "Generando proyecto de pruebas en ${TARGET_DIR} (repo CuyScout: ${REPO_DIR}) ..."
( cd "${REPO_DIR}" && swift run cuyscout init "${TARGET_DIR}" "${ARGS[@]}" )
