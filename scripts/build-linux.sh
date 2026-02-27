#!/usr/bin/env bash
set -euo pipefail

PROFILE="full"
BUILD_DIR="build"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            PROFILE="${2:-}"
            shift 2
            ;;
        --build-dir)
            BUILD_DIR="${2:-}"
            shift 2
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            echo "usage: $0 [--profile full|minimal] [--build-dir <path>]" >&2
            exit 1
            ;;
    esac
done

if [[ "${PROFILE}" != "full" && "${PROFILE}" != "minimal" ]]; then
    echo "error: invalid profile '${PROFILE}', expected 'full' or 'minimal'" >&2
    exit 1
fi

CMAKE_ARGS=(
    -DCMAKE_BUILD_TYPE=Release
    "-DSPACE_BUILD_PROFILE=${PROFILE}"
)
if [[ "${PROFILE}" == "minimal" ]]; then
    CMAKE_ARGS+=(-DSPACE_ENABLE_CEF=OFF)
fi

cmake -B "${BUILD_DIR}" "${CMAKE_ARGS[@]}"
cmake --build "${BUILD_DIR}" --config Release

PACKAGE_MARKER="${BUILD_DIR}/.package-build-start"
rm -f "${PACKAGE_MARKER}"
touch "${PACKAGE_MARKER}"
(
    cd "${BUILD_DIR}"
    cpack -G DEB
    cpack -G RPM
)

mkdir -p "${BUILD_DIR}/dist"
rm -rf "${BUILD_DIR}/dist/assets"
cp -r assets "${BUILD_DIR}/dist/assets"
cp "${BUILD_DIR}/space" "${BUILD_DIR}/dist/"

if [[ "${PROFILE}" == "minimal" ]]; then
    BIN_TAR_NAME="space-minimal-linux-x86_64-bin.tar.gz"
    APPIMAGE_BASE="space-minimal"
    STABLE_APPIMAGE_NAME="space-minimal-linux-x86_64.AppImage"
    STABLE_DEB_NAME="space-minimal-linux-amd64.deb"
    STABLE_RPM_NAME="space-minimal-linux-x86_64.rpm"
else
    BIN_TAR_NAME="space-linux-x86_64-bin.tar.gz"
    APPIMAGE_BASE="space"
    STABLE_APPIMAGE_NAME="space-linux-x86_64.AppImage"
    STABLE_DEB_NAME="space-linux-amd64.deb"
    STABLE_RPM_NAME="space-linux-x86_64.rpm"
fi

tar -czf "${BUILD_DIR}/dist/${BIN_TAR_NAME}" -C "${BUILD_DIR}/dist" space assets

SPACE_BUILD_DIR="${BUILD_DIR}" SPACE_APPIMAGE_BASENAME="${APPIMAGE_BASE}" scripts/build-appimage.sh

APPIMAGE_SRC="$(ls -t "${BUILD_DIR}"/"${APPIMAGE_BASE}"-*-x86_64.AppImage | head -n1)"
DEB_SRC="$(
    find "${BUILD_DIR}" -maxdepth 1 -type f -name 'space-*-Linux.deb' -newer "${PACKAGE_MARKER}" -print \
        | sort \
        | head -n1
)"
RPM_SRC="$(
    find "${BUILD_DIR}" -maxdepth 1 -type f -name 'space-*-Linux.rpm' -newer "${PACKAGE_MARKER}" -print \
        | sort \
        | head -n1
)"
rm -f "${PACKAGE_MARKER}"

if [[ -z "${DEB_SRC}" || -z "${RPM_SRC}" ]]; then
    echo "error: failed to locate generated DEB/RPM packages in ${BUILD_DIR}" >&2
    exit 1
fi
if [[ -z "${APPIMAGE_SRC}" ]]; then
    echo "error: failed to locate generated AppImage in ${BUILD_DIR}" >&2
    exit 1
fi

cp "${APPIMAGE_SRC}" "${BUILD_DIR}/${STABLE_APPIMAGE_NAME}"
cp "${DEB_SRC}" "${BUILD_DIR}/${STABLE_DEB_NAME}"
cp "${RPM_SRC}" "${BUILD_DIR}/${STABLE_RPM_NAME}"
