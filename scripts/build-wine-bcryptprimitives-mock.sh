#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/windows}"
OUTPUT_PATH="${1:-${BUILD_DIR}/bcryptprimitives.dll}"
CC="${CC:-x86_64-w64-mingw32-gcc-posix}"

if ! command -v "${CC}" >/dev/null 2>&1; then
    echo "Missing required compiler: ${CC}" >&2
    exit 1
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "${tmp_dir}"
}
trap cleanup EXIT

cat > "${tmp_dir}/bcryptprimitives_mock.c" <<'SRC'
#include <windows.h>

BOOL ProcessPrng(PBYTE pbData, SIZE_T cbData)
{
    (void)pbData;
    (void)cbData;
    return TRUE;
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved)
{
    (void)module;
    (void)reason;
    (void)reserved;
    return TRUE;
}
SRC

"${CC}" -s -Os -shared \
    -o "${OUTPUT_PATH}" \
    "${tmp_dir}/bcryptprimitives_mock.c" \
    -Wl,--out-implib,"${tmp_dir}/libbcryptprimitives.a"

echo "Wrote ${OUTPUT_PATH}"
