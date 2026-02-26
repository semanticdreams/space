#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
APPIMAGE_WORK_DIR="${BUILD_DIR}/appimage"
APPDIR="${APPIMAGE_WORK_DIR}/AppDir"
TOOLS_DIR="${APPIMAGE_WORK_DIR}/tools"
LINUXDEPLOY_URL="${LINUXDEPLOY_URL:-https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20240109-1/linuxdeploy-x86_64.AppImage}"
APPIMAGETOOL_URL="${APPIMAGETOOL_URL:-https://github.com/AppImage/AppImageKit/releases/download/12/appimagetool-x86_64.AppImage}"

if [[ ! -f "${BUILD_DIR}/space" ]]; then
    echo "error: ${BUILD_DIR}/space not found; run make build first" >&2
    exit 1
fi

mkdir -p "${APPDIR}/usr/bin" \
         "${APPDIR}/usr/lib" \
         "${APPDIR}/usr/share/space" \
         "${APPDIR}/usr/share/applications" \
         "${APPDIR}/usr/share/icons/hicolor/256x256/apps" \
         "${TOOLS_DIR}"

rm -rf "${APPDIR}/usr/bin/space" \
       "${APPDIR}/usr/share/space/assets" \
       "${APPDIR}/usr/share/applications/space.desktop" \
       "${APPDIR}/usr/share/icons/hicolor/256x256/apps/space.png" \
       "${APPDIR}/usr/lib/locales"

cp "${BUILD_DIR}/space" "${APPDIR}/usr/bin/space"
cp -r "${ROOT_DIR}/assets" "${APPDIR}/usr/share/space/assets"
cp "${ROOT_DIR}/assets/pics/space.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/space.png"

if [[ -f "${BUILD_DIR}/space.desktop" ]]; then
    cp "${BUILD_DIR}/space.desktop" "${APPDIR}/usr/share/applications/space.desktop"
else
    cat > "${APPDIR}/usr/share/applications/space.desktop" <<'DESKTOP'
[Desktop Entry]
Name=space
Comment=space
Exec=space %U
Icon=space
Terminal=false
Type=Application
Categories=Game;
DESKTOP
fi

copy_if_exists() {
    local src="$1"
    local dst="$2"
    if [[ -e "${src}" ]]; then
        cp -a "${src}" "${dst}"
    fi
}

download_with_retry() {
    local url="$1"
    local output="$2"
    local attempts=5
    local delay=2
    local i
    for ((i = 1; i <= attempts; ++i)); do
        if curl -fL --retry 3 --retry-delay 1 --connect-timeout 10 "$url" -o "$output"; then
            return 0
        fi
        if [[ "$i" -lt "$attempts" ]]; then
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done
    return 1
}

ensure_tool() {
    local tool_path="$1"
    local tool_url="$2"
    local stamp_path="$3"
    local current_url=""
    if [[ -f "${stamp_path}" ]]; then
        current_url="$(cat "${stamp_path}")"
    fi
    if [[ ! -x "${tool_path}" || "${current_url}" != "${tool_url}" ]]; then
        download_with_retry "${tool_url}" "${tool_path}"
        chmod +x "${tool_path}"
        printf '%s' "${tool_url}" > "${stamp_path}"
    fi
}

copy_if_exists "${BUILD_DIR}/libcef.so" "${APPDIR}/usr/lib/"
copy_if_exists "${BUILD_DIR}/resources.pak" "${APPDIR}/usr/lib/"
copy_if_exists "${BUILD_DIR}/icudtl.dat" "${APPDIR}/usr/lib/"
copy_if_exists "${BUILD_DIR}/v8_context_snapshot.bin" "${APPDIR}/usr/lib/"
copy_if_exists "${BUILD_DIR}/snapshot_blob.bin" "${APPDIR}/usr/lib/"
copy_if_exists "${BUILD_DIR}/chrome_100_percent.pak" "${APPDIR}/usr/lib/"
copy_if_exists "${BUILD_DIR}/chrome_200_percent.pak" "${APPDIR}/usr/lib/"
copy_if_exists "${BUILD_DIR}/locales" "${APPDIR}/usr/lib/"

if compgen -G "${BUILD_DIR}/external/sdl/libSDL3.so*" > /dev/null; then
    cp -a ${BUILD_DIR}/external/sdl/libSDL3.so* "${APPDIR}/usr/lib/"
fi

copy_if_exists "${ROOT_DIR}/ffi/matrix/target/release/libmatrix.so" "${APPDIR}/usr/lib/"

cat > "${APPDIR}/AppRun" <<'APP_RUN'
#!/bin/sh
set -eu
HERE="$(dirname "$(readlink -f "$0")")"
export SPACE_ASSETS_PATH="$HERE/usr/share/space/assets"
if [ -d "$HERE/usr/lib" ]; then
    export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
exec "$HERE/usr/bin/space" "$@"
APP_RUN
chmod +x "${APPDIR}/AppRun"

LINUXDEPLOY="${TOOLS_DIR}/linuxdeploy-x86_64.AppImage"
APPIMAGETOOL="${TOOLS_DIR}/appimagetool-x86_64.AppImage"
ensure_tool "${LINUXDEPLOY}" "${LINUXDEPLOY_URL}" "${LINUXDEPLOY}.url"
ensure_tool "${APPIMAGETOOL}" "${APPIMAGETOOL_URL}" "${APPIMAGETOOL}.url"

APPIMAGELAUNCHER_DISABLE=1 APPIMAGE_EXTRACT_AND_RUN=1 "${LINUXDEPLOY}" \
    --appdir "${APPDIR}" \
    --executable "${APPDIR}/usr/bin/space" \
    --desktop-file "${APPDIR}/usr/share/applications/space.desktop" \
    --icon-file "${APPDIR}/usr/share/icons/hicolor/256x256/apps/space.png"

VERSION="$(sed -n 's/^set(CPACK_PACKAGE_VERSION \"\\(.*\\)\")/\\1/p' "${BUILD_DIR}/CPackConfig.cmake" | head -n1)"
if [[ -z "${VERSION}" ]]; then
    VERSION="0.1.0"
fi
OUT_APPIMAGE="${BUILD_DIR}/space-${VERSION}-x86_64.AppImage"
APPIMAGE_MARKER="${BUILD_DIR}/.appimage-build-start"

rm -f "${OUT_APPIMAGE}"
rm -f "${APPIMAGE_MARKER}"
touch "${APPIMAGE_MARKER}"
(
    cd "${BUILD_DIR}"
    APPIMAGELAUNCHER_DISABLE=1 APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 "${APPIMAGETOOL}" "${APPDIR}"
)

GENERATED_APPIMAGE="$(
    find "${BUILD_DIR}" -maxdepth 1 -type f -name '*.AppImage' -newer "${APPIMAGE_MARKER}" -print \
        | sort \
        | head -n1
)"
rm -f "${APPIMAGE_MARKER}"
if [[ -z "${GENERATED_APPIMAGE}" ]]; then
    echo "error: appimagetool did not produce an AppImage in ${BUILD_DIR}" >&2
    exit 1
fi
if [[ "${GENERATED_APPIMAGE}" != "${OUT_APPIMAGE}" ]]; then
    mv -f "${GENERATED_APPIMAGE}" "${OUT_APPIMAGE}"
fi

echo "AppImage generated: ${OUT_APPIMAGE}"
