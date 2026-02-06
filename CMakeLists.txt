cmake_minimum_required(VERSION 3.18.0)
set(CMAKE_CXX_STANDARD 17)
project(space VERSION 0.1.0)
set(OpenGL_GL_PREFERENCE "GLVND")

include(CTest)
enable_testing()

option(SPACE_BUILD_MATRIX "Build Matrix Rust library" ON)
option(SPACE_SUPPRESS_THIRD_PARTY_WARNINGS "Suppress warnings from third-party libraries" ON)
option(SPACE_ENABLE_WALLET_CORE "Build wallet-core integration" OFF)

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
endif()
pkg_check_modules(ZMQ REQUIRED IMPORTED_TARGET libzmq)
pkg_check_modules(PORTAUDIO REQUIRED IMPORTED_TARGET portaudio-2.0)
pkg_check_modules(AUBIO REQUIRED IMPORTED_TARGET aubio)
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
if(UNIX AND NOT APPLE)
    pkg_check_modules(LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1)
endif()

find_package(glm REQUIRED)

find_package(OpenGL REQUIRED COMPONENTS OpenGL)

find_package(SDL2 REQUIRED)
include_directories(${SDL2_INCLUDE_DIRS})

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

# Executable and link
string(STRIP ${SDL2_LIBRARIES} SDL2_LIBRARIES)

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
add_library(${PROJECT_NAME}_lib ${SOURCES})
if(SPACE_HAS_VTERM)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_HAS_VTERM=1)
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
    ${SDL2_LIBRARIES}
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
target_link_libraries(${PROJECT_NAME}_lib PkgConfig::EPOXY)
if(SPACE_ENABLE_WALLET_CORE)
    target_link_libraries(${PROJECT_NAME}_lib TrustWalletCore)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_ENABLE_WALLET_CORE=1)
endif()

if(WIN32)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_WINAPI=1)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_NAME=\"winapi\")
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_REASON=\"\")
    target_link_libraries(${PROJECT_NAME}_lib user32 shell32 advapi32)
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

add_test(NAME ${PROJECT_NAME}_fnl_tests
    COMMAND space -m tests.fast:main
)
set_tests_properties(${PROJECT_NAME}_fnl_tests PROPERTIES
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

set(CPACK_GENERATOR "DEB")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "space")
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
#set(CPACK_DEBIAN_PACKAGE_DEPENDS
#"libsdl2-2.0-0, libepoxy0, libbullet-dev, libopenal1"
#)
set(CPACK_DEBIAN_PACKAGE_DESCRIPTION "space")
set(CPACK_DEBIAN_PACKAGE_SECTION "games")

include(CPack)
