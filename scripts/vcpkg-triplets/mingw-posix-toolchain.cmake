set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

if(CMAKE_HOST_WIN32)
    set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc.exe CACHE STRING "")
    set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++.exe CACHE STRING "")
    set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres.exe CACHE STRING "")
    find_program(SPACE_RC_PREPROCESSOR_PATH NAMES ${CMAKE_C_COMPILER} REQUIRED)
else()
    set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc-posix CACHE STRING "")
    set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++-posix CACHE STRING "")
    set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres CACHE STRING "")
    set(SPACE_RC_PREPROCESSOR_PATH ${CMAKE_C_COMPILER})
endif()
set(CMAKE_RC_FLAGS_INIT "--preprocessor=${SPACE_RC_PREPROCESSOR_PATH}" CACHE STRING "")

# MinGW import libs are commonly named *.dll.a; make find_library resolve them
# for vcpkg wrapper modules (e.g. zlib/freetype transitive resolution).
set(CMAKE_FIND_LIBRARY_PREFIXES "lib" "" CACHE STRING "")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".dll.a" ".a" ".lib" CACHE STRING "")
