cmake_minimum_required(VERSION 3.18.0)
set(CMAKE_CXX_STANDARD 17)
project(space VERSION 0.1.0)
set(OpenGL_GL_PREFERENCE "GLVND")

include(CTest)
enable_testing()
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/cef-defaults.cmake)

option(SPACE_BUILD_MATRIX "Build Matrix Rust library" ON)
option(SPACE_SUPPRESS_THIRD_PARTY_WARNINGS "Suppress warnings from third-party libraries" ON)
option(SPACE_ENABLE_WALLET_CORE "Build wallet-core integration" OFF)
option(SPACE_ENABLE_LIBTORRENT "Build libtorrent-rasterbar integration" ON)
option(SPACE_ENABLE_FFMPEG "Build FFmpeg-backed in-world video support" ON)
option(SPACE_ENABLE_CEF "Enable CEF embedded browser support" ${SPACE_DEFAULT_ENABLE_CEF})
set(SPACE_CEF_VERSION "${SPACE_CEF_LINUX_VERSION_DEFAULT}" CACHE STRING "Pinned CEF build version")
set(SPACE_CEF_URL "${SPACE_CEF_LINUX_URL_DEFAULT}" CACHE STRING "Pinned CEF archive URL")
set(SPACE_CEF_SHA256 "${SPACE_CEF_LINUX_SHA256_DEFAULT}" CACHE STRING "Pinned CEF archive SHA256")
set(SPACE_CEF_DOWNLOAD_DIR "${CMAKE_BINARY_DIR}/_deps/cef" CACHE PATH "Directory used to cache downloaded CEF archives")
if(SPACE_ENABLE_CEF)
    set(CMAKE_CXX_STANDARD 20)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    if(NOT SPACE_CEF_VERSION)
        set(SPACE_CEF_VERSION "${SPACE_CEF_LINUX_VERSION_DEFAULT}" CACHE STRING "Pinned CEF build version" FORCE)
    endif()
    if(NOT SPACE_CEF_URL)
        set(SPACE_CEF_URL "${SPACE_CEF_LINUX_URL_DEFAULT}" CACHE STRING "Pinned CEF archive URL" FORCE)
    endif()
    if(NOT SPACE_CEF_SHA256)
        set(SPACE_CEF_SHA256 "${SPACE_CEF_LINUX_SHA256_DEFAULT}" CACHE STRING "Pinned CEF archive SHA256" FORCE)
    endif()
endif()

function(space_suppress_target_warnings target_name)
    if(TARGET ${target_name})
        get_target_property(target_type ${target_name} TYPE)
        if(target_type STREQUAL "INTERFACE_LIBRARY")
            if(MSVC)
                target_compile_options(${target_name} INTERFACE /W0)
            else()
                target_compile_options(${target_name} INTERFACE -w)
            endif()
        else()
            if(MSVC)
                target_compile_options(${target_name} PRIVATE /W0)
            else()
                target_compile_options(${target_name} PRIVATE -w)
            endif()
        endif()
    endif()
endfunction()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build static libraries")
add_subdirectory(external/lua)

add_subdirectory(external/sqlite)

add_subdirectory(external/tree-sitter)
if(WIN32)
    set(SPACE_ENABLE_WALLET_CORE OFF)
endif()
if(SPACE_ENABLE_WALLET_CORE)
    set(TW_UNIT_TESTS OFF CACHE BOOL "Disable wallet-core unit tests" FORCE)
    set(TW_BUILD_EXAMPLES OFF CACHE BOOL "Disable wallet-core examples" FORCE)
    set(TW_TREZOR_TESTS OFF CACHE BOOL "Disable trezor-crypto tests" FORCE)
    add_subdirectory(external/wallet-core)
endif()

set(MSDF_ATLAS_BUILD_STANDALONE OFF CACHE BOOL "Disable msdf-atlas-gen standalone build" FORCE)
set(MSDF_ATLAS_USE_VCPKG OFF CACHE BOOL "Disable msdf-atlas-gen vcpkg integration" FORCE)
set(MSDF_ATLAS_USE_SKIA OFF CACHE BOOL "Disable msdf-atlas-gen Skia integration" FORCE)
set(MSDF_ATLAS_INSTALL OFF CACHE BOOL "Disable msdf-atlas-gen install targets" FORCE)
set(MSDFGEN_BUILD_STANDALONE OFF CACHE BOOL "Disable msdfgen standalone build" FORCE)
set(MSDFGEN_USE_VCPKG OFF CACHE BOOL "Disable msdfgen vcpkg integration" FORCE)
set(MSDFGEN_USE_SKIA OFF CACHE BOOL "Disable msdfgen Skia integration" FORCE)
add_subdirectory(external/msdf-atlas-gen)

set(LIBJPEG_TURBO_ALLOW_SUBPROJECT ON CACHE BOOL "Allow libjpeg-turbo subproject" FORCE)
set(LIBJPEG_TURBO_BUILD_TOOLS OFF CACHE BOOL "Disable libjpeg-turbo tools" FORCE)
set(LIBJPEG_TURBO_BUILD_TESTS OFF CACHE BOOL "Disable libjpeg-turbo tests" FORCE)
set(ENABLE_SHARED OFF CACHE BOOL "Disable libjpeg-turbo shared build" FORCE)
set(ENABLE_STATIC ON CACHE BOOL "Enable libjpeg-turbo static build" FORCE)
set(WITH_TURBOJPEG OFF CACHE BOOL "Disable TurboJPEG API" FORCE)
set(WITH_JAVA OFF CACHE BOOL "Disable libjpeg-turbo Java" FORCE)
set(WITH_FUZZ OFF CACHE BOOL "Disable libjpeg-turbo fuzz targets" FORCE)
set(WITH_SIMD OFF CACHE BOOL "Disable libjpeg-turbo SIMD" FORCE)
add_subdirectory(external/libjpeg-turbo)

include_directories(SYSTEM ${CMAKE_SOURCE_DIR}/external/sol2)

include_directories(SYSTEM ${CMAKE_SOURCE_DIR}/external/cgltf)
include_directories(SYSTEM ${CMAKE_SOURCE_DIR}/external/cppzmq/include)

find_package(PkgConfig REQUIRED)
set(SPACE_HAS_VTERM OFF)
if(UNIX AND NOT APPLE)
    pkg_check_modules(VTERM REQUIRED IMPORTED_TARGET vterm)
    set(SPACE_HAS_VTERM ON)
    pkg_check_modules(LIBGCCJIT IMPORTED_TARGET libgccjit)
    if(NOT LIBGCCJIT_FOUND)
        find_path(LIBGCCJIT_INCLUDE_DIR
            NAMES libgccjit.h
            PATHS
                /usr/lib/gcc/x86_64-linux-gnu/11/include
                /usr/lib/gcc/x86_64-linux-gnu/12/include
                /usr/lib/gcc/x86_64-linux-gnu/13/include
                /usr/include
        )
        find_library(LIBGCCJIT_LIBRARY
            NAMES gccjit libgccjit
            PATHS
                /usr/lib/gcc/x86_64-linux-gnu/11
                /usr/lib/gcc/x86_64-linux-gnu/12
                /usr/lib/gcc/x86_64-linux-gnu/13
                /usr/lib/x86_64-linux-gnu
                /usr/lib
        )
        if(NOT LIBGCCJIT_INCLUDE_DIR OR NOT LIBGCCJIT_LIBRARY)
            message(FATAL_ERROR "libgccjit not found. Install libgccjit-11-dev (or equivalent).")
        endif()
        add_library(space_gccjit INTERFACE)
        target_include_directories(space_gccjit SYSTEM INTERFACE ${LIBGCCJIT_INCLUDE_DIR})
        target_link_libraries(space_gccjit INTERFACE ${LIBGCCJIT_LIBRARY})
    endif()
endif()
pkg_check_modules(ZMQ REQUIRED IMPORTED_TARGET libzmq)
pkg_check_modules(PORTAUDIO REQUIRED IMPORTED_TARGET portaudio-2.0)
pkg_check_modules(AUBIO REQUIRED IMPORTED_TARGET aubio)
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
pkg_check_modules(XAPIAN REQUIRED IMPORTED_TARGET xapian-core)
if(UNIX AND NOT APPLE)
    pkg_check_modules(LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1)
endif()

set(SPACE_HAS_LIBTORRENT OFF)
if(SPACE_ENABLE_LIBTORRENT)
    pkg_check_modules(LIBTORRENT_RASTERBAR IMPORTED_TARGET libtorrent-rasterbar)
    if(LIBTORRENT_RASTERBAR_FOUND)
        set(SPACE_HAS_LIBTORRENT ON)
    else()
        message(WARNING "libtorrent-rasterbar-dev not found (pkg-config: libtorrent-rasterbar); libtorrent Lua module will be unavailable.")
    endif()
endif()

set(SPACE_HAS_FFMPEG OFF)
if(SPACE_ENABLE_FFMPEG)
    pkg_check_modules(FFMPEG_AVFORMAT IMPORTED_TARGET libavformat)
    pkg_check_modules(FFMPEG_AVCODEC IMPORTED_TARGET libavcodec)
    pkg_check_modules(FFMPEG_AVUTIL IMPORTED_TARGET libavutil)
    pkg_check_modules(FFMPEG_SWSCALE IMPORTED_TARGET libswscale)
    pkg_check_modules(FFMPEG_SWRESAMPLE IMPORTED_TARGET libswresample)
    if(FFMPEG_AVFORMAT_FOUND AND FFMPEG_AVCODEC_FOUND AND FFMPEG_AVUTIL_FOUND AND FFMPEG_SWSCALE_FOUND AND FFMPEG_SWRESAMPLE_FOUND)
        set(SPACE_HAS_FFMPEG ON)
    else()
        message(WARNING "FFmpeg dev packages not found (need libavformat/libavcodec/libavutil/libswscale/libswresample); video module will be unavailable.")
    endif()
endif()

find_package(glm REQUIRED)

find_package(OpenGL REQUIRED COMPONENTS OpenGL)

find_package(OpenGL)

find_package(Bullet REQUIRED)
include_directories(${BULLET_INCLUDE_DIRS})

find_package(OpenAL REQUIRED)
include_directories(${OPENAL_INCLUDE_DIR})

find_package(PNG REQUIRED)

#find_package(Python3 REQUIRED COMPONENTS Interpreter Development)
#include_directories(Python3_INCLUDE_DIRS)

find_package(pybind11 CONFIG)

find_package(OpenMP REQUIRED)
find_package(CURL REQUIRED)
set(SPDLOG_BUILD_SHARED OFF CACHE BOOL "Disable spdlog shared build" FORCE)
set(SPDLOG_BUILD_TESTS OFF CACHE BOOL "Disable spdlog tests" FORCE)
set(SPDLOG_BUILD_EXAMPLE OFF CACHE BOOL "Disable spdlog examples" FORCE)
set(SPDLOG_INSTALL OFF CACHE BOOL "Disable spdlog install" FORCE)
add_subdirectory(external/spdlog)
set(SDL_SHARED ON CACHE BOOL "Build SDL3 shared library" FORCE)
set(SDL_STATIC OFF CACHE BOOL "Disable SDL3 static library build" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "Disable SDL3 test helper library" FORCE)
set(SDL_TESTS OFF CACHE BOOL "Disable SDL3 tests" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "Disable SDL3 examples" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "Disable SDL3 install rules" FORCE)
add_subdirectory(external/sdl)
if(SPACE_SUPPRESS_THIRD_PARTY_WARNINGS)
    space_suppress_target_warnings(lua)
    space_suppress_target_warnings(lua-header)
    space_suppress_target_warnings(sqlite3)
    space_suppress_target_warnings(lsqlite3)
    space_suppress_target_warnings(tree_sitter_core)
    space_suppress_target_warnings(tree_sitter_cpp)
    space_suppress_target_warnings(tree_sitter_python)
    space_suppress_target_warnings(tree_sitter_fennel)
    space_suppress_target_warnings(tree_sitter_javascript)
    space_suppress_target_warnings(TrustWalletCore)
    space_suppress_target_warnings(msdf-atlas-gen)
    space_suppress_target_warnings(jpeg-static)
    space_suppress_target_warnings(spdlog)
    space_suppress_target_warnings(spdlog_header_only)
endif()

if(UNIX AND NOT APPLE)
    pkg_check_modules(GTK3 IMPORTED_TARGET gtk+-3.0)
    pkg_check_modules(APPINDICATOR IMPORTED_TARGET ayatana-appindicator3-0.1)
    pkg_check_modules(LIBNOTIFY IMPORTED_TARGET libnotify)
endif()

if(POLICY CMP0167)
    cmake_policy(SET CMP0167 NEW)
endif()
find_package(Boost CONFIG REQUIRED)

file( GLOB SOURCES src/*.cpp src/*.c)
if(NOT SPACE_HAS_VTERM)
    list(REMOVE_ITEM SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/src/terminal.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_terminal.cpp
    )
endif()
if(NOT SPACE_ENABLE_WALLET_CORE)
    list(REMOVE_ITEM SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_wallet_core.cpp
    )
endif()
if(NOT SPACE_HAS_LIBTORRENT)
    list(REMOVE_ITEM SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_libtorrent.cpp
    )
endif()
add_library(${PROJECT_NAME}_lib ${SOURCES})
if(SPACE_HAS_VTERM)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_HAS_VTERM=1)
endif()
if(SPACE_ENABLE_CEF)
    if(NOT UNIX OR APPLE)
        message(FATAL_ERROR "SPACE_ENABLE_CEF currently supports Linux only")
    endif()
    include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/cef.cmake)
    target_compile_features(${PROJECT_NAME}_lib PUBLIC cxx_std_20)
    space_setup_cef_for_target(${PROJECT_NAME}_lib)
endif()
target_include_directories(${PROJECT_NAME}_lib
    PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/ffi/matrix/include
)
target_include_directories(${PROJECT_NAME}_lib
    SYSTEM PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/external/nlohmann
    ${CMAKE_CURRENT_SOURCE_DIR}/external/tomlplusplus/include
)
target_include_directories(${PROJECT_NAME}_lib
    SYSTEM PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/external/libjpeg-turbo
    ${CMAKE_CURRENT_BINARY_DIR}/external/libjpeg-turbo
)
target_link_libraries(${PROJECT_NAME}_lib
    SDL3::SDL3
    ${BULLET_LIBRARIES}
    ${OPENAL_LIBRARY}
    PNG::PNG
    jpeg-static
    msdf-atlas-gen::msdf-atlas-gen
    util
    OpenGL::GL
    #Python3::Python
    glm::glm
    CURL::libcurl
    lua
    sqlite3
    lsqlite3
    PkgConfig::ZMQ
    PkgConfig::PORTAUDIO
    PkgConfig::AUBIO
    PkgConfig::XAPIAN
    tree_sitter_core
    tree_sitter_cpp
    tree_sitter_python
    tree_sitter_fennel
    tree_sitter_javascript
    OpenMP::OpenMP_CXX
    spdlog::spdlog
    Boost::headers
)
if(SPACE_HAS_VTERM)
    target_link_libraries(${PROJECT_NAME}_lib PkgConfig::VTERM)
endif()
if(UNIX AND NOT APPLE)
    if(LIBGCCJIT_FOUND)
        target_link_libraries(${PROJECT_NAME}_lib PkgConfig::LIBGCCJIT)
    else()
        target_link_libraries(${PROJECT_NAME}_lib space_gccjit)
    endif()
endif()
target_link_libraries(${PROJECT_NAME}_lib PkgConfig::EPOXY)
if(SPACE_ENABLE_WALLET_CORE)
    target_link_libraries(${PROJECT_NAME}_lib TrustWalletCore)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_ENABLE_WALLET_CORE=1)
endif()
if(SPACE_HAS_LIBTORRENT)
    target_link_libraries(${PROJECT_NAME}_lib PkgConfig::LIBTORRENT_RASTERBAR)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_ENABLE_LIBTORRENT=1)
endif()
if(SPACE_HAS_FFMPEG)
    target_link_libraries(${PROJECT_NAME}_lib
        PkgConfig::FFMPEG_AVFORMAT
        PkgConfig::FFMPEG_AVCODEC
        PkgConfig::FFMPEG_AVUTIL
        PkgConfig::FFMPEG_SWSCALE
        PkgConfig::FFMPEG_SWRESAMPLE
    )
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_HAS_FFMPEG=1)
endif()

if(WIN32)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_WINAPI=1)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_NAME=\"winapi\")
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_REASON=\"\")
    target_link_libraries(${PROJECT_NAME}_lib user32 shell32 advapi32 psapi)
elseif(APPLE)
    find_library(APPKIT_FRAMEWORK AppKit)
    find_library(FOUNDATION_FRAMEWORK Foundation)
    find_library(OBJC_LIBRARY objc)
    if(APPKIT_FRAMEWORK AND FOUNDATION_FRAMEWORK AND OBJC_LIBRARY)
        target_link_libraries(${PROJECT_NAME}_lib ${APPKIT_FRAMEWORK} ${FOUNDATION_FRAMEWORK} ${OBJC_LIBRARY})
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_APPKIT=1)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_NAME=\"appkit\")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_REASON=\"\")
    else()
        message(WARNING "AppKit/Foundation/objc not found; tray support disabled on macOS builds.")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_NONE=1)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_NAME=\"none\")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_REASON=\"AppKit/Foundation/objc frameworks not found during build.\")
    endif()
elseif(UNIX AND NOT APPLE)
    if(GTK3_FOUND AND APPINDICATOR_FOUND)
        target_link_libraries(${PROJECT_NAME}_lib PkgConfig::GTK3 PkgConfig::APPINDICATOR)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC
            TRAY_APPINDICATOR=1
            TRAY_BACKEND_NAME="ayatana-appindicator"
            TRAY_BACKEND_REASON=""
        )
    else()
        message(WARNING "AppIndicator/GTK3 not found; tray support disabled on Linux builds.")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC
            TRAY_BACKEND_NONE=1
            TRAY_BACKEND_NAME="none"
        )
        if(NOT GTK3_FOUND)
            set(TRAY_BACKEND_REASON "GTK3 development files not found during build.")
        elseif(NOT APPINDICATOR_FOUND)
            set(TRAY_BACKEND_REASON "AppIndicator development files not found during build (install libayatana-appindicator3-dev on Debian/Ubuntu).")
        else()
            set(TRAY_BACKEND_REASON "Tray backend disabled during build.")
        endif()
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_REASON="${TRAY_BACKEND_REASON}")
    endif()
    target_link_libraries(${PROJECT_NAME}_lib PkgConfig::LIBSECRET)
endif()

if(APPLE)
    find_library(APPLICATIONSERVICES_FRAMEWORK ApplicationServices)
    find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
    find_library(SECURITY_FRAMEWORK Security)
    if(APPLICATIONSERVICES_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME}_lib ${APPLICATIONSERVICES_FRAMEWORK})
    else()
        message(WARNING "ApplicationServices framework not found; webbrowser support disabled on macOS builds.")
    endif()
    if(COREFOUNDATION_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME}_lib ${COREFOUNDATION_FRAMEWORK})
    else()
        message(WARNING "CoreFoundation framework not found; webbrowser support disabled on macOS builds.")
    endif()
    if(SECURITY_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME}_lib ${SECURITY_FRAMEWORK})
    else()
        message(WARNING "Security framework not found; keyring support may be unavailable on macOS builds.")
    endif()
endif()

if(WIN32)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NONE=1)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NAME=\"none\")
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_REASON=\"notifications not implemented on Windows builds.\")
elseif(APPLE)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NONE=1)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NAME=\"none\")
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_REASON=\"notifications not implemented on macOS builds.\")
elseif(UNIX AND NOT APPLE)
    if(LIBNOTIFY_FOUND)
        target_link_libraries(${PROJECT_NAME}_lib PkgConfig::LIBNOTIFY)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_LIBNOTIFY=1)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NAME=\"libnotify\")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_REASON=\"\")
    else()
        message(WARNING "libnotify not found; notifications disabled on Linux builds.")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NONE=1)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NAME=\"none\")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_REASON=\"libnotify development files not found during build.\")
    endif()
else()
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NONE=1)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NAME=\"none\")
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_REASON=\"notification backend unavailable on this platform.\")
endif()

add_executable(${PROJECT_NAME} apps/space/main.cpp)
target_link_libraries(${PROJECT_NAME} ${PROJECT_NAME}_lib)
target_include_directories(${PROJECT_NAME} SYSTEM PRIVATE ${CMAKE_CURRENT_LIST_DIR}/external/CLI11/include)
if(SPACE_ENABLE_CEF)
    target_compile_definitions(${PROJECT_NAME} PUBLIC SPACE_ENABLE_CEF=1)
    space_setup_cef_for_target(${PROJECT_NAME})
endif()

if(SPACE_ENABLE_CEF)
    add_executable(space_cef_helper
        apps/space/cef_subprocess_main.cpp
        src/cef_runtime.cpp
    )
    target_include_directories(space_cef_helper PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_compile_definitions(space_cef_helper PUBLIC SPACE_ENABLE_CEF=1)
    space_setup_cef_for_target(space_cef_helper)
endif()

add_test(NAME ${PROJECT_NAME}_fnl_tests
    COMMAND space -m tests.fast:main
)
set_tests_properties(${PROJECT_NAME}_fnl_tests PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_input_dial_type
    tests/test_input_dial_type.cpp
    src/dial_type.cpp
    src/input_dial_type.cpp
    src/input_state.cpp
    src/input_gamepad_state.cpp
)
target_include_directories(test_input_dial_type PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(test_input_dial_type SDL3::SDL3)
add_test(NAME test_input_dial_type COMMAND test_input_dial_type)
set_tests_properties(test_input_dial_type PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_dotenv
    tests/test_dotenv.cpp
    src/dotenv.cpp
)
target_include_directories(test_dotenv PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_dotenv COMMAND test_dotenv)
set_tests_properties(test_dotenv PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_dotenv_integration
    tests/test_dotenv_integration.cpp
)
add_test(NAME test_dotenv_integration COMMAND test_dotenv_integration)
set_tests_properties(test_dotenv_integration PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_audio_stream_clock
    tests/test_audio_stream_clock.cpp
    src/audio.cpp
)
target_include_directories(test_audio_stream_clock PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(test_audio_stream_clock
    ${OPENAL_LIBRARY}
    glm::glm
)
add_test(NAME test_audio_stream_clock COMMAND test_audio_stream_clock)
set_tests_properties(test_audio_stream_clock PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_video_telemetry
    tests/test_video_telemetry.cpp
)
target_include_directories(test_video_telemetry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_video_telemetry COMMAND test_video_telemetry)
set_tests_properties(test_video_telemetry PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_lua_gccjit_binding
    tests/test_lua_gccjit_binding.cpp
    src/lua_gccjit.cpp
)
target_include_directories(test_lua_gccjit_binding PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)
target_link_libraries(test_lua_gccjit_binding lua)
if(UNIX AND NOT APPLE)
    if(LIBGCCJIT_FOUND)
        target_link_libraries(test_lua_gccjit_binding PkgConfig::LIBGCCJIT)
    else()
        target_link_libraries(test_lua_gccjit_binding space_gccjit)
    endif()
endif()
add_test(NAME test_lua_gccjit_binding COMMAND test_lua_gccjit_binding)
set_tests_properties(test_lua_gccjit_binding PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

target_compile_options(${PROJECT_NAME} PRIVATE -O2 -g)
target_link_options(${PROJECT_NAME} PRIVATE -O2 -g)

set_target_properties(${PROJECT_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)

# Optional Rust Matrix bridge build.
if(SPACE_BUILD_MATRIX)
    find_program(CARGO_EXECUTABLE cargo)
    if(CARGO_EXECUTABLE)
        set(MATRIX_DIR ${CMAKE_SOURCE_DIR}/ffi/matrix)
        set(MATRIX_TARGET_DIR ${MATRIX_DIR}/target/release)
        set(MATRIX_OUTPUT ${MATRIX_TARGET_DIR}/libmatrix${CMAKE_SHARED_LIBRARY_SUFFIX})
        add_custom_command(
            OUTPUT ${MATRIX_OUTPUT}
            COMMAND ${CARGO_EXECUTABLE} build --release
            WORKING_DIRECTORY ${MATRIX_DIR}
            DEPENDS ${MATRIX_DIR}/Cargo.toml ${MATRIX_DIR}/src/lib.rs
            BYPRODUCTS ${MATRIX_OUTPUT}
            COMMENT "---- Build matrix (Rust)"
        )
        add_custom_target(matrix_build ALL DEPENDS ${MATRIX_OUTPUT})
        add_dependencies(${PROJECT_NAME}_lib matrix_build)
        add_dependencies(${PROJECT_NAME} matrix_build)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_MATRIX_ENABLED=1)
        target_link_directories(${PROJECT_NAME}_lib PRIVATE ${MATRIX_TARGET_DIR})
        target_link_directories(${PROJECT_NAME} PRIVATE ${MATRIX_TARGET_DIR})
        target_link_libraries(${PROJECT_NAME}_lib matrix)
        target_link_libraries(${PROJECT_NAME} matrix)
        set_target_properties(${PROJECT_NAME} PROPERTIES
            BUILD_RPATH "\$ORIGIN/../ffi/matrix/target/release"
            INSTALL_RPATH "\$ORIGIN/../lib"
        )
        install(FILES ${MATRIX_OUTPUT} DESTINATION lib)
    else()
        message(WARNING "cargo not found; matrix build disabled.")
    endif()
endif()

# Copying assets to the build folder
add_custom_command(
        TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_LIST_DIR}/assets
        $<TARGET_FILE_DIR:${PROJECT_NAME}>/assets
        COMMENT "---- Copy Assets"
)

set(CPACK_PROJECT_NAME ${PROJECT_NAME})
set(CPACK_PROJECT_VERSION ${PROJECT_VERSION})

# Install the executable to /usr/bin
install(TARGETS ${PROJECT_NAME}
    RUNTIME DESTINATION bin
)

# Install the assets folder to /usr/share/space/assets
install(DIRECTORY assets/ DESTINATION share/${PROJECT_NAME}/assets)

# Path where the generated desktop file will go
set(DESKTOP_FILE ${CMAKE_BINARY_DIR}/space.desktop)

# Generate the .desktop file
file(WRITE ${DESKTOP_FILE} 
"[Desktop Entry]\n"
"Name=${CPACK_PROJECT_NAME}\n"
"Comment=space\n"
"Exec=${CPACK_PROJECT_NAME} %U\n"
"Icon=${CPACK_PROJECT_NAME}\n"
"Terminal=false\n"
"Type=Application\n"
"Categories=Game;\n"
)

# Install the generated desktop file
install(FILES ${DESKTOP_FILE} DESTINATION share/applications)
install(FILES assets/pics/space.png DESTINATION share/icons/hicolor/256x256/apps)

set(CPACK_GENERATOR "DEB;RPM")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "space")
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
#set(CPACK_DEBIAN_PACKAGE_DEPENDS
#"libsdl3-0, libepoxy0, libbullet-dev, libopenal1"
#)
set(CPACK_DEBIAN_PACKAGE_DESCRIPTION "space")
set(CPACK_DEBIAN_PACKAGE_SECTION "games")
set(CPACK_RPM_PACKAGE_LICENSE "GPLv3")
set(CPACK_RPM_PACKAGE_RELEASE "1")
set(CPACK_RPM_PACKAGE_GROUP "Amusements/Games")
set(CPACK_RPM_PACKAGE_DESCRIPTION "space")

include(CPack)
