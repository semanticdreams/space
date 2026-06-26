#!/usr/bin/env bash
set -euo pipefail

ROOT=""
PROFILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            ROOT="${2:-}"
            shift 2
            ;;
        --profile)
            PROFILE="${2:-}"
            shift 2
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${ROOT}" ]]; then
    echo "error: --root is required" >&2
    exit 1
fi
if [[ "${PROFILE}" != "full" && "${PROFILE}" != "minimal" ]]; then
    echo "error: --profile must be 'full' or 'minimal'" >&2
    exit 1
fi

test -x "${ROOT}/bin/space"
test -f "${ROOT}/share/space/assets/lua/main.fnl"

if [[ "${PROFILE}" == "full" ]]; then
    test -x "${ROOT}/bin/space_cef_helper"
    test -f "${ROOT}/lib/space/cef/libcef.so"
    test -f "${ROOT}/lib/space/cef/libEGL.so"
    test -f "${ROOT}/lib/space/cef/libGLESv2.so"
    test -f "${ROOT}/lib/space/cef/libvk_swiftshader.so"
    test -f "${ROOT}/lib/space/cef/libvulkan.so.1"
    test -f "${ROOT}/lib/space/cef/vk_swiftshader_icd.json"
    test -f "${ROOT}/lib/space/cef/icudtl.dat"
    test -f "${ROOT}/lib/space/cef/chrome_100_percent.pak"
    test -f "${ROOT}/lib/space/cef/chrome_200_percent.pak"
    test -f "${ROOT}/lib/space/cef/resources.pak"
    test -f "${ROOT}/lib/space/cef/v8_context_snapshot.bin"
    test -d "${ROOT}/lib/space/cef/locales"
else
    test ! -e "${ROOT}/bin/space_cef_helper"
    test ! -e "${ROOT}/lib/space/cef"
    test ! -e "${ROOT}/lib/libcef.so"
fi
