cmake_minimum_required(VERSION 3.12.0)
set(CMAKE_CXX_STANDARD 17)
project(space VERSION 0.1.0)
set(OpenGL_GL_PREFERENCE "GLVND")

include(CTest)
enable_testing()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build static libraries")
add_subdirectory(external/lua)

add_subdirectory(external/sqlite)

include_directories(${CMAKE_SOURCE_DIR}/external/sol2)

include_directories(${CMAKE_SOURCE_DIR}/external/stb)

find_package(glm REQUIRED)

find_package(OpenGL REQUIRED COMPONENTS OpenGL)

find_package(SDL2 REQUIRED)
include_directories(${SDL2_INCLUDE_DIRS})

find_package(GLEW REQUIRED)
include_directories(${GLEW_INCLUDE_DIRS})

find_package(OpenGL)

find_package(Bullet REQUIRED)
include_directories(${BULLET_INCLUDE_DIRS})

find_package(OpenAL REQUIRED)
include_directories(${OPENAL_INCLUDE_DIR})

find_package(Python3 REQUIRED COMPONENTS Interpreter Development)
include_directories(Python3_INCLUDE_DIRS)

find_package(pybind11 CONFIG)

find_package(OpenMP REQUIRED)

# Executable and link
string(STRIP ${SDL2_LIBRARIES} SDL2_LIBRARIES)

file( GLOB SOURCES src/*.cpp src/*.c)
add_executable(${PROJECT_NAME} ${SOURCES})
target_link_libraries(${PROJECT_NAME}
    ${SDL2_LIBRARIES}
    ${GLEW_LIBRARIES}
    ${BULLET_LIBRARIES}
    ${OPENAL_LIBRARY}
    OpenGL::GL
    Python3::Python
    glm::glm
    lua
    sqlite3
    lsqlite3
    OpenMP::OpenMP_CXX
)

target_compile_options(${PROJECT_NAME} PRIVATE -O2 -g)
target_link_options(${PROJECT_NAME} PRIVATE -O2 -g)

set_target_properties(${PROJECT_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)

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
#"libsdl2-2.0-0, libglew2.2, libbullet-dev, libopenal1"
#)
set(CPACK_DEBIAN_PACKAGE_DESCRIPTION "space")
set(CPACK_DEBIAN_PACKAGE_SECTION "games")

include(CPack)
