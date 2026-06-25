#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SPACE_BUILD_DIR:-${ROOT_DIR}/build}"
if [[ "${BUILD_DIR}" != /* ]]; then
    BUILD_DIR="${ROOT_DIR}/${BUILD_DIR}"
fi
INSTALL_PREFIX="${SPACE_INSTALL_PREFIX:-}"
APPIMAGE_WORK_DIR="${BUILD_DIR}/appimage"
APPDIR="${APPIMAGE_WORK_DIR}/AppDir"
TOOLS_DIR="${APPIMAGE_WORK_DIR}/tools"
APPIMAGE_BASENAME="${SPACE_APPIMAGE_BASENAME:-space}"
LINUXDEPLOY_URL="${LINUXDEPLOY_URL:-https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20240109-1/linuxdeploy-x86_64.AppImage}"
APPIMAGETOOL_URL="${APPIMAGETOOL_URL:-https://github.com/AppImage/AppImageKit/releases/download/12/appimagetool-x86_64.AppImage}"

USE_INSTALL_TREE=false
if [[ -n "${INSTALL_PREFIX}" && -d "${INSTALL_PREFIX}/bin" ]]; then
    USE_INSTALL_TREE=true
fi

if [[ "${USE_INSTALL_TREE}" == false && ! -f "${BUILD_DIR}/space" ]]; then
    echo "error: ${BUILD_DIR}/space not found; run make build first" >&2
    exit 1
fi

rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr/bin" \
         "${APPDIR}/usr/lib" \
         "${APPDIR}/usr/share" \
         "${TOOLS_DIR}"

if [[ "${USE_INSTALL_TREE}" == true ]]; then
    cp -a "${INSTALL_PREFIX}/bin" "${APPDIR}/usr/"
    if [[ -d "${INSTALL_PREFIX}/lib" ]]; then
        cp -a "${INSTALL_PREFIX}/lib" "${APPDIR}/usr/"
    fi
    cp -a "${INSTALL_PREFIX}/share" "${APPDIR}/usr/"
else
    copy_if_exists() {
        local src="$1"
        local dst="$2"
        if [[ -e "${src}" ]]; then
            cp -a "${src}" "${dst}"
        fi
    }

    copy_required() {
        local src="$1"
        local dst="$2"
        if [[ ! -e "${src}" ]]; then
            echo "error: required AppImage input missing: ${src}" >&2
            exit 1
        fi
        cp -a "${src}" "${dst}"
    }

    cp "${BUILD_DIR}/space" "${APPDIR}/usr/bin/space"
    mkdir -p "${APPDIR}/usr/share/space"
    cp -r "${ROOT_DIR}/assets" "${APPDIR}/usr/share/space/assets"
    mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"
    cp "${ROOT_DIR}/assets/pics/space.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/space.png"

    mkdir -p "${APPDIR}/usr/share/applications"
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

    CEF_ENABLED=false
    if [[ -f "${BUILD_DIR}/CMakeCache.txt" ]] && grep -Eq '^SPACE_ENABLE_CEF:BOOL=(ON|TRUE|1)$' "${BUILD_DIR}/CMakeCache.txt"; then
        CEF_ENABLED=true
    fi

    if [[ "${CEF_ENABLED}" == true ]]; then
        cef_dst="${APPDIR}/usr/lib/space/cef"
        mkdir -p "${cef_dst}"
        copy_required "${BUILD_DIR}/space_cef_helper" "${APPDIR}/usr/bin/"
        copy_required "${BUILD_DIR}/libcef.so" "${cef_dst}/"
        copy_required "${BUILD_DIR}/libEGL.so" "${cef_dst}/"
        copy_required "${BUILD_DIR}/libGLESv2.so" "${cef_dst}/"
        copy_required "${BUILD_DIR}/libvk_swiftshader.so" "${cef_dst}/"
        copy_required "${BUILD_DIR}/libvulkan.so.1" "${cef_dst}/"
        copy_required "${BUILD_DIR}/vk_swiftshader_icd.json" "${cef_dst}/"
        copy_required "${BUILD_DIR}/resources.pak" "${cef_dst}/"
        copy_required "${BUILD_DIR}/icudtl.dat" "${cef_dst}/"
        copy_required "${BUILD_DIR}/v8_context_snapshot.bin" "${cef_dst}/"
        copy_if_exists "${BUILD_DIR}/snapshot_blob.bin" "${cef_dst}/"
        copy_required "${BUILD_DIR}/chrome_100_percent.pak" "${cef_dst}/"
        copy_required "${BUILD_DIR}/chrome_200_percent.pak" "${cef_dst}/"
        copy_required "${BUILD_DIR}/locales" "${cef_dst}/"
    fi

    if compgen -G "${BUILD_DIR}/external/sdl/libSDL3.so*" > /dev/null; then
        cp -a ${BUILD_DIR}/external/sdl/libSDL3.so* "${APPDIR}/usr/lib/"
    fi

    copy_if_exists "${ROOT_DIR}/ffi/matrix/target/release/libmatrix.so" "${APPDIR}/usr/lib/"
fi

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

cat > "${APPDIR}/AppRun" <<'APP_RUN'
#!/bin/sh
set -eu
HERE="$(dirname "$(readlink -f "$0")")"
export SPACE_ASSETS_PATH="$HERE/usr/share/space/assets"
if [ -d "$HERE/usr/lib" ]; then
    export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
if [ -d "$HERE/usr/lib/space/cef" ]; then
    export LD_LIBRARY_PATH="$HERE/usr/lib/space/cef${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
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

if [[ ! -f "${BUILD_DIR}/CPackConfig.cmake" ]]; then
    echo "error: ${BUILD_DIR}/CPackConfig.cmake not found; package metadata is required for AppImage versioning" >&2
    exit 1
fi
VERSION="$(
    sed -nE 's/^set\(CPACK_PACKAGE_VERSION[[:space:]]+"?([^")]+)"?\)$/\1/p' "${BUILD_DIR}/CPackConfig.cmake" \
        | head -n1
)"
if [[ -z "${VERSION}" ]]; then
    echo "error: failed to resolve CPACK_PACKAGE_VERSION from ${BUILD_DIR}/CPackConfig.cmake" >&2
    exit 1
fi
OUT_APPIMAGE="${BUILD_DIR}/${APPIMAGE_BASENAME}-${VERSION}-x86_64.AppImage"
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
