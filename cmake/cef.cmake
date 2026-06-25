if(NOT DEFINED SPACE_CEF_VERSION)
    set(SPACE_CEF_VERSION "" CACHE STRING "Pinned CEF version identifier")
endif()
if(NOT DEFINED SPACE_CEF_URL)
    set(SPACE_CEF_URL "" CACHE STRING "Pinned CEF download URL")
endif()
if(NOT DEFINED SPACE_CEF_SHA256)
    set(SPACE_CEF_SHA256 "" CACHE STRING "Pinned CEF archive SHA256")
endif()
if(NOT DEFINED SPACE_CEF_DOWNLOAD_DIR)
    set(SPACE_CEF_DOWNLOAD_DIR "${CMAKE_BINARY_DIR}/_deps/cef" CACHE PATH "Directory used to cache downloaded CEF archives")
endif()

function(space_require_cef_config)
    if(NOT SPACE_CEF_VERSION)
        message(FATAL_ERROR "SPACE_ENABLE_CEF=ON requires SPACE_CEF_VERSION to be set")
    endif()
    if(NOT SPACE_CEF_URL)
        message(FATAL_ERROR "SPACE_ENABLE_CEF=ON requires SPACE_CEF_URL to be set")
    endif()
    if(NOT SPACE_CEF_SHA256)
        message(FATAL_ERROR "SPACE_ENABLE_CEF=ON requires SPACE_CEF_SHA256 to be set")
    endif()
endfunction()

function(space_download_with_retries url destination expected_sha256)
    set(_space_download_attempt 1)
    set(_space_download_max_attempts 5)
    set(_space_download_done FALSE)
    set(_space_download_last_code 0)
    set(_space_download_last_message "")
    set(_space_download_last_log "")

    while((NOT _space_download_done) AND (_space_download_attempt LESS_EQUAL _space_download_max_attempts))
        if(_space_download_attempt GREATER 1)
            message(STATUS "Retrying CEF download (${_space_download_attempt}/${_space_download_max_attempts})")
        endif()

        file(DOWNLOAD
            "${url}"
            "${destination}"
            EXPECTED_HASH "SHA256=${expected_sha256}"
            SHOW_PROGRESS
            TLS_VERIFY ON
            STATUS _space_download_status
            LOG _space_download_log
        )
        list(GET _space_download_status 0 _space_download_code)
        list(GET _space_download_status 1 _space_download_message)

        if(_space_download_code EQUAL 0)
            set(_space_download_done TRUE)
        else()
            set(_space_download_last_code "${_space_download_code}")
            set(_space_download_last_message "${_space_download_message}")
            set(_space_download_last_log "${_space_download_log}")
            file(REMOVE "${destination}")
            math(EXPR _space_download_attempt "${_space_download_attempt} + 1")
        endif()
    endwhile()

    if(NOT _space_download_done)
        message(FATAL_ERROR
            "Failed to download CEF archive (${_space_download_last_code}: ${_space_download_last_message}). "
            "Log: ${_space_download_last_log}")
    endif()
endfunction()

function(space_setup_cef_for_target target_name)
    if(WIN32)
        message(FATAL_ERROR "CEF integration for Windows is not implemented yet")
    elseif(APPLE)
        message(FATAL_ERROR "CEF integration for macOS is not implemented yet")
    elseif(UNIX)
        space_setup_cef_for_target_linux(${target_name})
    else()
        message(FATAL_ERROR "Unsupported platform for CEF integration")
    endif()
endfunction()

function(space_setup_cef_for_target_linux target_name)
    if(NOT UNIX OR APPLE)
        message(FATAL_ERROR "space_setup_cef_for_target_linux requires Linux")
    endif()

    space_require_cef_config()

    file(MAKE_DIRECTORY "${SPACE_CEF_DOWNLOAD_DIR}")

    get_filename_component(_cef_archive_name "${SPACE_CEF_URL}" NAME)
    if(_cef_archive_name STREQUAL "")
        message(FATAL_ERROR "SPACE_CEF_URL must point to an archive file")
    endif()

    set(_cef_archive_path "${SPACE_CEF_DOWNLOAD_DIR}/${_cef_archive_name}")
    set(_cef_extract_stamp "${SPACE_CEF_DOWNLOAD_DIR}/.extract-${SPACE_CEF_VERSION}.stamp")

    if(EXISTS "${_cef_archive_path}")
        file(SHA256 "${_cef_archive_path}" _cef_archive_sha)
        if(NOT _cef_archive_sha STREQUAL "${SPACE_CEF_SHA256}")
            message(STATUS "CEF archive hash mismatch, deleting stale archive ${_cef_archive_path}")
            file(REMOVE "${_cef_archive_path}")
        endif()
    endif()

    if(NOT EXISTS "${_cef_archive_path}")
        message(STATUS "Downloading CEF ${SPACE_CEF_VERSION} from ${SPACE_CEF_URL}")
        space_download_with_retries("${SPACE_CEF_URL}" "${_cef_archive_path}" "${SPACE_CEF_SHA256}")
    endif()

    if(NOT EXISTS "${_cef_extract_stamp}")
        file(GLOB _old_cef_dirs "${SPACE_CEF_DOWNLOAD_DIR}/cef_binary_*")
        foreach(_old_dir IN LISTS _old_cef_dirs)
            if(IS_DIRECTORY "${_old_dir}")
                file(REMOVE_RECURSE "${_old_dir}")
            endif()
        endforeach()

        message(STATUS "Extracting CEF archive ${_cef_archive_path}")
        file(ARCHIVE_EXTRACT INPUT "${_cef_archive_path}" DESTINATION "${SPACE_CEF_DOWNLOAD_DIR}")
        file(GLOB _post_extract_candidates_raw "${SPACE_CEF_DOWNLOAD_DIR}/cef_binary_*")
        set(_post_extract_candidates "")
        foreach(_cef_candidate IN LISTS _post_extract_candidates_raw)
            if(IS_DIRECTORY "${_cef_candidate}")
                list(APPEND _post_extract_candidates "${_cef_candidate}")
            endif()
        endforeach()

        list(LENGTH _post_extract_candidates _post_extract_count)
        if(_post_extract_count LESS 1)
            find_program(SPACE_TAR_EXECUTABLE tar)
            if(NOT SPACE_TAR_EXECUTABLE)
                message(FATAL_ERROR
                    "Failed to extract CEF archive with CMake and no tar executable is available")
            endif()
            message(STATUS "CMake extraction produced no directory, retrying with tar")
            execute_process(
                COMMAND "${SPACE_TAR_EXECUTABLE}" -xjf "${_cef_archive_path}"
                WORKING_DIRECTORY "${SPACE_CEF_DOWNLOAD_DIR}"
                RESULT_VARIABLE _cef_tar_result
                OUTPUT_VARIABLE _cef_tar_stdout
                ERROR_VARIABLE _cef_tar_stderr
            )
            if(NOT _cef_tar_result EQUAL 0)
                message(FATAL_ERROR
                    "Failed to extract CEF archive with tar (${_cef_tar_result}): ${_cef_tar_stderr}")
            endif()
        endif()
    endif()

    file(GLOB _cef_root_candidates_raw "${SPACE_CEF_DOWNLOAD_DIR}/cef_binary_*")
    set(_cef_root_candidates "")
    foreach(_cef_candidate IN LISTS _cef_root_candidates_raw)
        if(IS_DIRECTORY "${_cef_candidate}")
            list(APPEND _cef_root_candidates "${_cef_candidate}")
        endif()
    endforeach()

    list(LENGTH _cef_root_candidates _cef_root_count)
    if(_cef_root_count LESS 1)
        message(STATUS "CEF extract stamp exists but no extracted directory was found; retrying extraction")
        file(GLOB _old_cef_dirs "${SPACE_CEF_DOWNLOAD_DIR}/cef_binary_*")
        foreach(_old_dir IN LISTS _old_cef_dirs)
            if(IS_DIRECTORY "${_old_dir}")
                file(REMOVE_RECURSE "${_old_dir}")
            endif()
        endforeach()
        file(REMOVE "${_cef_extract_stamp}")

        file(ARCHIVE_EXTRACT INPUT "${_cef_archive_path}" DESTINATION "${SPACE_CEF_DOWNLOAD_DIR}")
        file(GLOB _cef_root_candidates_raw_retry "${SPACE_CEF_DOWNLOAD_DIR}/cef_binary_*")
        set(_cef_root_candidates "")
        foreach(_cef_candidate IN LISTS _cef_root_candidates_raw_retry)
            if(IS_DIRECTORY "${_cef_candidate}")
                list(APPEND _cef_root_candidates "${_cef_candidate}")
            endif()
        endforeach()
        list(LENGTH _cef_root_candidates _cef_root_count)

        if(_cef_root_count LESS 1)
            find_program(SPACE_TAR_EXECUTABLE tar)
            if(NOT SPACE_TAR_EXECUTABLE)
                message(FATAL_ERROR
                    "Failed to locate extracted CEF directory in ${SPACE_CEF_DOWNLOAD_DIR} "
                    "and no tar executable is available for fallback extraction")
            endif()
            execute_process(
                COMMAND "${SPACE_TAR_EXECUTABLE}" -xjf "${_cef_archive_path}"
                WORKING_DIRECTORY "${SPACE_CEF_DOWNLOAD_DIR}"
                RESULT_VARIABLE _cef_tar_result_retry
                OUTPUT_VARIABLE _cef_tar_stdout_retry
                ERROR_VARIABLE _cef_tar_stderr_retry
            )
            if(NOT _cef_tar_result_retry EQUAL 0)
                message(FATAL_ERROR
                    "Failed to extract CEF archive with tar (${_cef_tar_result_retry}): ${_cef_tar_stderr_retry}")
            endif()
            file(GLOB _cef_root_candidates_raw_retry2 "${SPACE_CEF_DOWNLOAD_DIR}/cef_binary_*")
            set(_cef_root_candidates "")
            foreach(_cef_candidate IN LISTS _cef_root_candidates_raw_retry2)
                if(IS_DIRECTORY "${_cef_candidate}")
                    list(APPEND _cef_root_candidates "${_cef_candidate}")
                endif()
            endforeach()
            list(LENGTH _cef_root_candidates _cef_root_count)
        endif()
    endif()
    if(_cef_root_count LESS 1)
        message(FATAL_ERROR "Failed to locate extracted CEF directory in ${SPACE_CEF_DOWNLOAD_DIR}")
    endif()
    list(GET _cef_root_candidates 0 SPACE_CEF_ROOT)
    set(SPACE_CEF_ROOT "${SPACE_CEF_ROOT}" CACHE PATH "Resolved CEF root directory" FORCE)
    if(NOT EXISTS "${_cef_extract_stamp}")
        file(WRITE "${_cef_extract_stamp}" "${SPACE_CEF_VERSION}\n")
    endif()

    set(SPACE_CEF_ROOT "${SPACE_CEF_ROOT}" PARENT_SCOPE)

    set(_cef_include_dir "${SPACE_CEF_ROOT}")
    set(_cef_lib_path "${SPACE_CEF_ROOT}/Release/libcef.so")
    if(NOT EXISTS "${_cef_lib_path}")
        message(FATAL_ERROR "CEF shared library not found at ${_cef_lib_path}")
    endif()

    # Chromium resolves icudtl.dat from the libcef module directory on Linux.
    # Ensure required runtime payloads are staged next to libcef.so.
    set(_cef_release_dir "${SPACE_CEF_ROOT}/Release")
    set(_cef_resource_dir "${SPACE_CEF_ROOT}/Resources")
    set(_cef_release_payloads
        "icudtl.dat"
        "resources.pak"
        "v8_context_snapshot.bin"
        "snapshot_blob.bin"
        "chrome_100_percent.pak"
        "chrome_200_percent.pak"
    )
    foreach(_cef_payload IN LISTS _cef_release_payloads)
        if(EXISTS "${_cef_resource_dir}/${_cef_payload}")
            file(COPY_FILE
                "${_cef_resource_dir}/${_cef_payload}"
                "${_cef_release_dir}/${_cef_payload}"
                ONLY_IF_DIFFERENT
            )
        endif()
    endforeach()
    if(EXISTS "${_cef_resource_dir}/locales")
        file(COPY "${_cef_resource_dir}/locales" DESTINATION "${_cef_release_dir}")
    endif()

    set(_cef_required_runtime_files
        "${SPACE_CEF_ROOT}/Release/libcef.so"
        "${SPACE_CEF_ROOT}/Release/libEGL.so"
        "${SPACE_CEF_ROOT}/Release/libGLESv2.so"
        "${SPACE_CEF_ROOT}/Release/libvk_swiftshader.so"
        "${SPACE_CEF_ROOT}/Release/libvulkan.so.1"
        "${SPACE_CEF_ROOT}/Release/vk_swiftshader_icd.json"
        "${SPACE_CEF_ROOT}/Release/chrome_100_percent.pak"
        "${SPACE_CEF_ROOT}/Release/chrome_200_percent.pak"
        "${SPACE_CEF_ROOT}/Release/icudtl.dat"
        "${SPACE_CEF_ROOT}/Release/resources.pak"
        "${SPACE_CEF_ROOT}/Release/v8_context_snapshot.bin"
    )
    foreach(_cef_required_file IN LISTS _cef_required_runtime_files)
        if(NOT EXISTS "${_cef_required_file}")
            message(FATAL_ERROR "Required CEF runtime file not found: ${_cef_required_file}")
        endif()
    endforeach()
    if(NOT EXISTS "${SPACE_CEF_ROOT}/Release/locales")
        message(FATAL_ERROR "Required CEF locales directory not found: ${SPACE_CEF_ROOT}/Release/locales")
    endif()

    if(NOT TARGET space_cef_linux)
        add_library(space_cef_linux SHARED IMPORTED GLOBAL)
    endif()
    set_target_properties(space_cef_linux PROPERTIES IMPORTED_LOCATION "${_cef_lib_path}")

    if(NOT TARGET libcef_dll_wrapper)
        set(USE_SANDBOX OFF CACHE BOOL "Disable CEF sandbox for Linux runtime" FORCE)
        set(CEF_ROOT "${SPACE_CEF_ROOT}")
        list(APPEND CMAKE_MODULE_PATH "${CEF_ROOT}/cmake")
        find_package(CEF REQUIRED)
        add_subdirectory(
            "${CEF_LIBCEF_DLL_WRAPPER_PATH}"
            "${CMAKE_BINARY_DIR}/_deps/cef/libcef_dll_wrapper_build"
        )
    endif()

    target_compile_definitions(${target_name} PUBLIC SPACE_ENABLE_CEF=1)
    target_include_directories(${target_name} SYSTEM PRIVATE "${_cef_include_dir}")
    target_link_libraries(${target_name} libcef_dll_wrapper space_cef_linux)

    set_property(TARGET ${target_name} APPEND PROPERTY BUILD_RPATH "${SPACE_CEF_ROOT}/Release")
    set_property(TARGET ${target_name} APPEND PROPERTY INSTALL_RPATH "\$ORIGIN/../lib/space/cef")

    if(NOT TARGET space_cef_runtime)
        add_custom_target(space_cef_runtime)

        foreach(_cef_file IN LISTS _cef_required_runtime_files)
            add_custom_command(
                TARGET space_cef_runtime POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${_cef_file}"
                        "${CMAKE_BINARY_DIR}"
                VERBATIM
            )
        endforeach()

        if(EXISTS "${SPACE_CEF_ROOT}/Release/snapshot_blob.bin")
            add_custom_command(
                TARGET space_cef_runtime POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${SPACE_CEF_ROOT}/Release/snapshot_blob.bin"
                        "${CMAKE_BINARY_DIR}"
                VERBATIM
            )
        endif()

        add_custom_command(
            TARGET space_cef_runtime POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                    "${SPACE_CEF_ROOT}/Release/locales"
                    "${CMAKE_BINARY_DIR}/locales"
            VERBATIM
        )
    endif()

    add_dependencies(${target_name} space_cef_runtime)
endfunction()
