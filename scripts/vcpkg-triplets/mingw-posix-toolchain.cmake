set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

if(CMAKE_HOST_WIN32)
    set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc.exe CACHE STRING "")
    set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++.exe CACHE STRING "")
    set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres.exe CACHE STRING "")
else()
    set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc-posix CACHE STRING "")
    set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++-posix CACHE STRING "")
    set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres CACHE STRING "")
endif()
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -print-prog-name=cc1
    OUTPUT_VARIABLE SPACE_CC1_PATH
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE SPACE_CC1_RESULT
)
if(SPACE_CC1_RESULT EQUAL 0 AND NOT SPACE_CC1_PATH STREQUAL "")
    get_filename_component(SPACE_CC1_DIR "${SPACE_CC1_PATH}" DIRECTORY)
    set(CMAKE_RC_FLAGS_INIT
        "--preprocessor=${CMAKE_C_COMPILER} --preprocessor-arg=-B${SPACE_CC1_DIR}"
        CACHE STRING ""
    )
else()
    set(CMAKE_RC_FLAGS_INIT "--preprocessor=${CMAKE_C_COMPILER}" CACHE STRING "")
endif()

# MinGW import libs are commonly named *.dll.a; make find_library resolve them
# for vcpkg wrapper modules (e.g. zlib/freetype transitive resolution).
set(CMAKE_FIND_LIBRARY_PREFIXES "lib" "" CACHE STRING "")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".dll.a" ".a" ".lib" CACHE STRING "")
