#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/windows}"
VCPKG_ROOT="${VCPKG_ROOT:-${ROOT_DIR}/vcpkg}"
VCPKG_TRIPLET="${VCPKG_TARGET_TRIPLET:-x64-mingw}"
VCPKG_PACKAGES="${VCPKG_PACKAGES:-sdl2 glew bullet3 glm openal-soft curl zeromq portaudio aubio}"
CROSS_CC="${CROSS_CC:-}"
CROSS_CXX="${CROSS_CXX:-}"
RUST_TARGET="${RUST_TARGET:-x86_64-pc-windows-gnu}"
CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER:-x86_64-w64-mingw32-gcc}"

if [ ! -d "${VCPKG_ROOT}" ]; then
    echo "VCPKG_ROOT not found: ${VCPKG_ROOT}" >&2
    echo "Set VCPKG_ROOT or clone vcpkg into ${ROOT_DIR}/vcpkg." >&2
    exit 1
fi

vcpkg_bin="${VCPKG_ROOT}/vcpkg"
if [ ! -x "${vcpkg_bin}" ] && [ -x "${vcpkg_bin}.exe" ]; then
    vcpkg_bin="${vcpkg_bin}.exe"
fi
if [ ! -x "${vcpkg_bin}" ]; then
    echo "vcpkg executable not found. Run bootstrap-vcpkg first." >&2
    exit 1
fi

triplet_file=""
for candidate in "${VCPKG_TRIPLET}" x64-mingw-dynamic x64-mingw-static; do
    for dir in "${VCPKG_ROOT}/triplets" "${VCPKG_ROOT}/triplets/community"; do
        if [ -f "${dir}/${candidate}.cmake" ]; then
            VCPKG_TRIPLET="${candidate}"
            triplet_file="${dir}/${candidate}.cmake"
            break
        fi
    done
    if [ -n "${triplet_file}" ]; then
        break
    fi
done
if [ -z "${triplet_file}" ]; then
    echo "Vcpkg triplet not found for mingw. Available mingw triplets:" >&2
    find "${VCPKG_ROOT}/triplets" "${VCPKG_ROOT}/triplets/community" -maxdepth 1 -name "*mingw*.cmake" -print >&2 || true
    exit 1
fi

export VCPKG_TARGET_TRIPLET="${VCPKG_TRIPLET}"

if [ -n "${VCPKG_PACKAGES}" ]; then
    vcpkg_env=()
    if [ -n "${CC:-}" ] || [ -n "${CXX:-}" ]; then
        vcpkg_env=(env -u CC -u CXX)
    fi
    "${vcpkg_env[@]}" "${vcpkg_bin}" install --triplet "${VCPKG_TRIPLET}" ${VCPKG_PACKAGES}
fi

if ! command -v rustc >/dev/null 2>&1; then
    curl -fsSL https://sh.rustup.rs | sh -s -- -y
fi
if [ -f "${HOME}/.cargo/env" ]; then
    # shellcheck disable=SC1090
    source "${HOME}/.cargo/env"
fi
if command -v rustup >/dev/null 2>&1; then
    rustup target add "${RUST_TARGET}"
fi

export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER

pkgconfig_paths=(
    "${VCPKG_ROOT}/installed/${VCPKG_TRIPLET}/lib/pkgconfig"
    "${VCPKG_ROOT}/installed/${VCPKG_TRIPLET}/share/pkgconfig"
)
for path in "${pkgconfig_paths[@]}"; do
    if [ -d "${path}" ]; then
        export PKG_CONFIG_PATH="${path}${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    fi
done

cmake_args=(
    -S "${ROOT_DIR}"
    -B "${BUILD_DIR}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_TOOLCHAIN_FILE="${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
    -DVCPKG_TARGET_TRIPLET="${VCPKG_TRIPLET}"
)
if [ -n "${CROSS_CC}" ]; then
    cmake_args+=(-DCMAKE_C_COMPILER="${CROSS_CC}")
fi
if [ -n "${CROSS_CXX}" ]; then
    cmake_args+=(-DCMAKE_CXX_COMPILER="${CROSS_CXX}")
fi

if [ -n "${CMAKE_GENERATOR:-}" ]; then
    cmake_args+=(-G "${CMAKE_GENERATOR}")
fi

cmake "${cmake_args[@]}"
cmake --build "${BUILD_DIR}" --config Release
