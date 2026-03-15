#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/windows}"
TARGET_EXE="${1:-${BUILD_DIR}/space.exe}"

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Missing required command: ${cmd}" >&2
        exit 1
    fi
}

require_cmd x86_64-w64-mingw32-objdump
require_cmd x86_64-w64-mingw32-gcc-posix

if [ ! -d "${BUILD_DIR}" ]; then
    echo "Missing build directory: ${BUILD_DIR}" >&2
    exit 1
fi
if [ ! -f "${TARGET_EXE}" ]; then
    echo "Missing target executable: ${TARGET_EXE}" >&2
    exit 1
fi

cache_file="${BUILD_DIR}/CMakeCache.txt"
VCPKG_ROOT="${VCPKG_ROOT:-}"
VCPKG_TRIPLET="${VCPKG_TARGET_TRIPLET:-}"

if [ -z "${VCPKG_ROOT}" ] && [ -f "${cache_file}" ]; then
    VCPKG_ROOT="$(sed -n 's/^Z_VCPKG_ROOT_DIR:INTERNAL=//p' "${cache_file}" | tail -n1)"
fi
if [ -z "${VCPKG_TRIPLET}" ] && [ -f "${cache_file}" ]; then
    VCPKG_TRIPLET="$(sed -n 's/^VCPKG_TARGET_TRIPLET:STRING=//p' "${cache_file}" | tail -n1)"
fi
if [ -z "${VCPKG_TRIPLET}" ]; then
    VCPKG_TRIPLET="x64-mingw-dynamic-posix"
fi

search_dirs=()
add_search_dir() {
    local dir="$1"
    if [ -d "${dir}" ]; then
        search_dirs+=("${dir}")
    fi
}

add_search_dir "${BUILD_DIR}"
if [ -n "${VCPKG_ROOT}" ]; then
    add_search_dir "${VCPKG_ROOT}/installed/${VCPKG_TRIPLET}/bin"
fi

copy_if_present() {
    local source="$1"
    local dest_name
    if [ ! -f "${source}" ]; then
        return 1
    fi
    dest_name="$(basename "${source}")"
    cp -f "${source}" "${BUILD_DIR}/${dest_name}"
    return 0
}

copy_mingw_runtime_dll() {
    local dll_name="$1"
    local source
    source="$(x86_64-w64-mingw32-gcc-posix -print-file-name="${dll_name}")"
    if [ -n "${source}" ] && [ "${source}" != "${dll_name}" ] && [ -f "${source}" ]; then
        cp -f "${source}" "${BUILD_DIR}/${dll_name}"
        return 0
    fi
    return 1
}

for dll in libstdc++-6.dll libgcc_s_seh-1.dll libwinpthread-1.dll libgomp-1.dll libssp-0.dll; do
    copy_mingw_runtime_dll "${dll}" || true
done

matrix_candidates=(
    "${ROOT_DIR}/ffi/matrix/target/x86_64-pc-windows-gnu/release/matrix.dll"
    "${ROOT_DIR}/ffi/matrix/target/release/matrix.dll"
)
for candidate in "${matrix_candidates[@]}"; do
    if copy_if_present "${candidate}"; then
        break
    fi
done

is_system_dll() {
    local name
    name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "${name}" in
        api-ms-win-*|ext-ms-*| \
        kernel32.dll|user32.dll|gdi32.dll|gdiplus.dll|advapi32.dll|ntdll.dll| \
        ws2_32.dll|mswsock.dll|iphlpapi.dll|dnsapi.dll| \
        secur32.dll|crypt32.dll|bcrypt.dll|bcryptprimitives.dll| \
        ole32.dll|oleaut32.dll|shell32.dll|shlwapi.dll|combase.dll| \
        comdlg32.dll|comctl32.dll|rpcrt4.dll|version.dll|winmm.dll| \
        setupapi.dll|imm32.dll|psapi.dll|msvcrt.dll)
            return 0
            ;;
    esac
    return 1
}

get_imports() {
    local pe_file="$1"
    x86_64-w64-mingw32-objdump -p "${pe_file}" | awk '/DLL Name:/{print $3}'
}

find_dll_source() {
    local dll_name="$1"
    local dir
    local candidate
    for dir in "${search_dirs[@]}"; do
        candidate="$(find "${dir}" -maxdepth 1 -type f -iname "${dll_name}" -print -quit 2>/dev/null || true)"
        if [ -n "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

queue=("${TARGET_EXE}")
if [ -f "${BUILD_DIR}/matrix.dll" ]; then
    queue+=("${BUILD_DIR}/matrix.dll")
fi

declare -A visited_files=()
declare -A missing_dlls=()

for ((idx = 0; idx < ${#queue[@]}; idx++)); do
    pe_file="${queue[$idx]}"
    if [ ! -f "${pe_file}" ]; then
        continue
    fi
    if [ "${visited_files["${pe_file}"]+set}" = "set" ]; then
        continue
    fi
    visited_files["${pe_file}"]=1

    while IFS= read -r dll_name; do
        [ -z "${dll_name}" ] && continue
        if is_system_dll "${dll_name}"; then
            continue
        fi

        dest_path="${BUILD_DIR}/${dll_name}"
        if [ ! -f "${dest_path}" ]; then
            source_path="$(find_dll_source "${dll_name}" || true)"
            if [ -n "${source_path}" ]; then
                cp -f "${source_path}" "${dest_path}"
            else
                missing_dlls["${dll_name}"]=1
                continue
            fi
        fi
        queue+=("${dest_path}")
    done < <(get_imports "${pe_file}")
done

if [ "${#missing_dlls[@]}" -gt 0 ]; then
    echo "Warning: unresolved DLL dependencies (often provided by Wine/Windows system DLLs):" >&2
    for dll in "${!missing_dlls[@]}"; do
        echo "  ${dll}" >&2
    done
fi

echo "Windows runtime prepared in ${BUILD_DIR}"
