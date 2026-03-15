#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/windows}"
TARGET_EXE="${1:-${BUILD_DIR}/space.exe}"

"${ROOT_DIR}/scripts/prepare-windows-runtime.sh" "${TARGET_EXE}"
"${ROOT_DIR}/scripts/build-wine-bcryptprimitives-mock.sh" "${BUILD_DIR}/bcryptprimitives.dll"

echo "Wine runtime prepared in ${BUILD_DIR}"
