set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(SPACE_WINDOWS_API_LEVEL "0x0600")

function(space_append_flag_once var flag)
    if(DEFINED ${var} AND NOT "${${var}}" STREQUAL "")
        set(current_value "${${var}}")
    else()
        set(current_value "")
    endif()

    if(NOT current_value MATCHES "(^| )${flag}($| )")
        if(current_value STREQUAL "")
            set(current_value "${flag}")
        else()
            set(current_value "${current_value} ${flag}")
        endif()
        set(${var} "${current_value}" PARENT_SCOPE)
    endif()
endfunction()

if(CMAKE_HOST_WIN32)
    set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc.exe CACHE STRING "")
    set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++.exe CACHE STRING "")
    set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres.exe CACHE STRING "")
else()
    set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc-posix CACHE STRING "")
    set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++-posix CACHE STRING "")
    set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres CACHE STRING "")
endif()

space_append_flag_once(CMAKE_C_FLAGS_INIT "-D_WIN32_WINNT=${SPACE_WINDOWS_API_LEVEL}")
space_append_flag_once(CMAKE_C_FLAGS_INIT "-DWINVER=${SPACE_WINDOWS_API_LEVEL}")
space_append_flag_once(CMAKE_CXX_FLAGS_INIT "-D_WIN32_WINNT=${SPACE_WINDOWS_API_LEVEL}")
space_append_flag_once(CMAKE_CXX_FLAGS_INIT "-DWINVER=${SPACE_WINDOWS_API_LEVEL}")
space_append_flag_once(CMAKE_RC_FLAGS_INIT "-D_WIN32_WINNT=${SPACE_WINDOWS_API_LEVEL}")
space_append_flag_once(CMAKE_RC_FLAGS_INIT "-DWINVER=${SPACE_WINDOWS_API_LEVEL}")

# MinGW import libs are commonly named *.dll.a; make find_library resolve them
# for vcpkg wrapper modules (e.g. zlib/freetype transitive resolution).
set(CMAKE_FIND_LIBRARY_PREFIXES "lib" "" CACHE STRING "")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".dll.a" ".a" ".lib" CACHE STRING "")
