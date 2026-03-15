set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc-posix CACHE STRING "")
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++-posix CACHE STRING "")
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres CACHE STRING "")

# MinGW import libs are commonly named *.dll.a; make find_library resolve them
# for vcpkg wrapper modules (e.g. zlib/freetype transitive resolution).
set(CMAKE_FIND_LIBRARY_PREFIXES "lib" "" CACHE STRING "")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".dll.a" ".a" ".lib" CACHE STRING "")
