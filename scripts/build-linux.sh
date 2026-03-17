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

RELEASE_MANIFEST="${BUILD_DIR}/release-artifacts-${PROFILE}.txt"
RELEASE_DEB_PATH="${BUILD_DIR}/${STABLE_DEB_NAME}"
RELEASE_RPM_PATH="${BUILD_DIR}/${STABLE_RPM_NAME}"
RELEASE_APPIMAGE_PATH="${BUILD_DIR}/${STABLE_APPIMAGE_NAME}"
RELEASE_TAR_PATH="${BUILD_DIR}/dist/${BIN_TAR_NAME}"

tar -czf "${RELEASE_TAR_PATH}" -C "${BUILD_DIR}/dist" space assets

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

cp "${APPIMAGE_SRC}" "${RELEASE_APPIMAGE_PATH}"
cp "${DEB_SRC}" "${RELEASE_DEB_PATH}"
cp "${RPM_SRC}" "${RELEASE_RPM_PATH}"

for artifact in \
    "${RELEASE_DEB_PATH}" \
    "${RELEASE_RPM_PATH}" \
    "${RELEASE_APPIMAGE_PATH}" \
    "${RELEASE_TAR_PATH}"
do
    if [[ ! -f "${artifact}" ]]; then
        echo "error: expected release artifact missing: ${artifact}" >&2
        exit 1
    fi
done

cat > "${RELEASE_MANIFEST}" <<EOF
${RELEASE_DEB_PATH}
${RELEASE_RPM_PATH}
${RELEASE_APPIMAGE_PATH}
${RELEASE_TAR_PATH}
EOF
