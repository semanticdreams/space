#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VCPKG_ROOT="${VCPKG_ROOT:-${ROOT_DIR}/vcpkg}"

sudo apt-get update || true
sudo apt-get install -y mingw-w64 cmake ninja-build git pkg-config nasm curl

pwsh_deb="/tmp/powershell_7.5.4-1.deb_amd64.deb"
if ! command -v pwsh >/dev/null 2>&1; then
    curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v7.5.4/powershell_7.5.4-1.deb_amd64.deb" -o "${pwsh_deb}"
    sudo apt-get install -y "${pwsh_deb}"
    rm -f "${pwsh_deb}"
fi

if [ ! -d "${VCPKG_ROOT}" ]; then
    git clone https://github.com/microsoft/vcpkg "${VCPKG_ROOT}"
fi

if [ ! -x "${VCPKG_ROOT}/vcpkg" ]; then
    "${VCPKG_ROOT}/bootstrap-vcpkg.sh"
fi

if ! command -v rustc >/dev/null 2>&1; then
    curl -fsSL https://sh.rustup.rs | sh -s -- -y
fi
if [ -f "${HOME}/.cargo/env" ]; then
    # shellcheck disable=SC1090
    source "${HOME}/.cargo/env"
fi
if command -v rustup >/dev/null 2>&1; then
    rustup target add "${RUST_TARGET:-x86_64-pc-windows-gnu}"
fi

export VCPKG_ROOT
export VCPKG_TARGET_TRIPLET="${VCPKG_TARGET_TRIPLET:-x64-mingw}"
export CROSS_CC="${CROSS_CC:-x86_64-w64-mingw32-gcc}"
export CROSS_CXX="${CROSS_CXX:-x86_64-w64-mingw32-g++}"
export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER:-x86_64-w64-mingw32-gcc}"

"${ROOT_DIR}/scripts/build-windows.sh"
