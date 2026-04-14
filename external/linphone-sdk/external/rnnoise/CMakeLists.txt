cmake_minimum_required(VERSION 3.22)

include(rnnoise_functions.cmake)

include(GNUInstallDirs)
include(CheckCCompilerFlag)

get_library_version(RNN_LIBRARY_VERSION RNN_LIBRARY_VERSION_MAJOR)
message(STATUS "RNNoise library version: ${RNN_LIBRARY_VERSION}")

get_package_version(PACKAGE_VERSION)
if(NOT PACKAGE_VERSION)
  set(PACKAGE_VERSION 0.2.0)
endif()
message(STATUS "RNNoise package version: ${PACKAGE_VERSION}")

string(REGEX
       REPLACE "^([0-9]+.[0-9]+\\.?([0-9]+)?).*"
               "\\1"
               PROJECT_VERSION
               ${PACKAGE_VERSION})
message(STATUS "RNNoise project version: ${PROJECT_VERSION}")

project(RNNoise LANGUAGES C VERSION ${PROJECT_VERSION})
enable_language(ASM)

include(rnnoise_config.cmake)


# enable RTCD for x86 architectures
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86|i386|i686|x86_64|AMD64")
    if(NOT (ANDROID OR IOS))
        set(RNN_ENABLE_X86_RTCD ON)
        message(STATUS "RTCD enabled on x86 architectures for RNNoise")
    else()
        set(RNN_ENABLE_X86_RTCD OFF)
    endif()
else()
    set(RNN_ENABLE_X86_RTCD OFF)
endif()

if(RNN_CPU_X86 OR RNN_CPU_X64)
    cmake_dependent_option(RNN_X86_MAY_HAVE_SSE "Does runtime check for SSE1 support for RNNoise" ON "SSE1_SUPPORTED" OFF)
    cmake_dependent_option(RNN_X86_MAY_HAVE_SSE2 "Does runtime check for SSE2 support for RNNoise" ON "SSE2_SUPPORTED" OFF)
    cmake_dependent_option(RNN_X86_MAY_HAVE_SSE4_1 "Does runtime check for SSE4.1 support for RNNoise" ON "SSE4_1_SUPPORTED" OFF)
    cmake_dependent_option(RNN_X86_MAY_HAVE_AVX2 "Does runtime check for AVX2 support for RNNoise" ON "AVX2_SUPPORTED" OFF)
    if(RNN_CPU_X64) # Assume 64 bit has SSE2 support
        cmake_dependent_option(RNN_X86_PRESUME_SSE "Assume target CPU has SSE1 support" ON "RNN_X86_MAY_HAVE_SSE" OFF)
        cmake_dependent_option(RNN_X86_PRESUME_SSE2 "Assume target CPU has SSE2 support" ON "RNN_X86_MAY_HAVE_SSE2" OFF)
    else()
        cmake_dependent_option(RNN_X86_PRESUME_SSE "Assume target CPU has SSE1 support" OFF "RNN_X86_MAY_HAVE_SSE" OFF)
        cmake_dependent_option(RNN_X86_PRESUME_SSE2 "Assume target CPU has SSE2 support" OFF "RNN_X86_MAY_HAVE_SSE2" OFF)
    endif()
endif()

if(RNN_CPU_X86 OR RNN_CPU_X64)
    add_feature_info(X86_MAY_HAVE_SSE RNN_X86_MAY_HAVE_SSE "does runtime check for SSE1 support for RNNoise")
    add_feature_info(X86_MAY_HAVE_SSE2 RNN_X86_MAY_HAVE_SSE2 "does runtime check for SSE2 support for RNNoise") 
    add_feature_info(X86_PRESUME_SSE RNN_X86_PRESUME_SSE "assume target CPU has SSE1 support for RNNoise")
    add_feature_info(X86_PRESUME_SSE2 RNN_X86_PRESUME_SSE2 "assume target CPU has SSE2 support for RNNoise")
    add_feature_info(X86_MAY_HAVE_SSE4_1 RNN_X86_MAY_HAVE_SSE4_1 "does runtime check for SSE4_1 support for RNNoise")
    add_feature_info(X86_MAY_HAVE_AVX2 RNN_X86_MAY_HAVE_AVX2 "does runtime check for AVX2 support for RNNoise")
endif()


set(PUBLIC_HEADERS include/rnnoise.h)
set(RNNOISE_SOURCES
    src/denoise.c
    src/celt_lpc.c
    src/kiss_fft.c
    src/nnet.c
    src/nnet_default.c
    src/parse_lpcnet_weights.c
    src/pitch.c
    src/rnn.c
    src/rnnoise_tables.c
)

set(RNN_SOURCES_SSE4_1 "${CMAKE_CURRENT_SOURCE_DIR}/src/x86/nnet_sse4_1.c")
set(RNN_SOURCES_AVX2 "${CMAKE_CURRENT_SOURCE_DIR}/src/x86/nnet_avx2.c")
set(RNN_SOURCES_X86_RTCD
  "${CMAKE_CURRENT_SOURCE_DIR}/src/x86/x86_dnn_map.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/x86/x86cpu.c"
)
if(RNN_ENABLE_X86_RTCD)
    list(APPEND RNNOISE_SOURCES
        ${RNN_SOURCES_SSE4_1}
        ${RNN_SOURCES_AVX2}
        ${RNN_SOURCES_X86_RTCD}
    )
endif()

# Get RNNoise model
# The model is downloaded, checked and extracted during configure step, then the file rnnoise_data.c is added to the sources.
# If the model already exist, we simply check the version by comparing the hash found in model_version with the hash of the archive.
# If this archive is not found or if the hash is wrong, the model is removed and the right one is downloaded.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/model_version" MODEL_HASH)
string(STRIP "${MODEL_HASH}" MODEL_HASH)
set(MODEL_FILE "rnnoise_data-${MODEL_HASH}.tar.gz")
set(MODEL_TAR_PATH "${CMAKE_CURRENT_BINARY_DIR}/${MODEL_FILE}")
set(MODEL_URL "https://download.linphone.org/files/${MODEL_FILE}")
set(RNNOISE_DATA_C "${CMAKE_CURRENT_BINARY_DIR}/src/rnnoise_data.c")

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/src")

# archive of the model
if(NOT EXISTS "${CMAKE_CURRENT_BINARY_DIR}/rnnoise_data-${MODEL_HASH}.tar.gz")
    execute_process(
        COMMAND curl -L -o "${MODEL_TAR_PATH}" "${MODEL_URL}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        RESULT_VARIABLE download_result
    )
    message(STATUS "Download RNNoise model")
    if(NOT ${download_result} EQUAL 0)
        message(FATAL_ERROR "Problem when downloading file ${MODEL_URL}")
    endif()
    if(EXISTS "${RNNOISE_DATA_C}")
        file(REMOVE "${RNNOISE_DATA_C}")
        message(STATUS "Remove found RNNOISE model as a new archive has been downloaded")        
    endif()
else()
    message(STATUS "Archive found for RNNoise")
endif()
# Verify checksum of archive
if(WIN32)
    # On Windows use PowerShell
    execute_process(
        COMMAND powershell -Command "Get-FileHash -Algorithm SHA256 '${MODEL_TAR_PATH}' | Select-Object -ExpandProperty Hash"
        OUTPUT_VARIABLE ACTUAL_CHECKSUM
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    string(TOLOWER "${ACTUAL_CHECKSUM}" ACTUAL_CHECKSUM)
else()
    execute_process(
        COMMAND sha256sum "${MODEL_TAR_PATH}"
        OUTPUT_VARIABLE CHECKSUM_OUTPUT
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    string(REGEX REPLACE "([^ ]+).*$" "\\1" ACTUAL_CHECKSUM "${CHECKSUM_OUTPUT}")
endif()
# Compare checksum with hash
if(NOT "${ACTUAL_CHECKSUM}" STREQUAL "${MODEL_HASH}")
    message(STATUS "Checksums do not match for ${MODEL_TAR_PATH}. Deleting the file...")
    file(REMOVE "${MODEL_TAR_PATH}")
    message(FATAL_ERROR "
        Checksums do not match for ${MODEL_TAR_PATH}.
        expected: ${MODEL_HASH}
        computed: ${ACTUAL_CHECKSUM}
        Delete file and re-run build.
    ")
endif()
# Extract model if not found
if(NOT EXISTS "${RNNOISE_DATA_C}")
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E tar xzf "${MODEL_TAR_PATH}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        RESULT_VARIABLE extract_result
    )
    message(STATUS "Extract RNNoise model")
    if(NOT ${extract_result} EQUAL 0)
        message(FATAL_ERROR "Problem with model extraction")
    endif()
else()
   message(STATUS "Keep RNNoise model found")
endif()
list(APPEND RNNOISE_SOURCES "${RNNOISE_DATA_C}")

if (RNN_ENABLE_X86_RTCD)
    if(SSE4_1_SUPPORTED)
        if(RNN_X86_MAY_HAVE_SSE4_1)
            if(MSVC)
                set_source_files_properties(${RNN_SOURCES_SSE4_1} PROPERTIES COMPILE_FLAGS "/arch:SSE2")
                set_source_files_properties(${RNN_SOURCES_SSE4_1} PROPERTIES COMPILE_DEFINITIONS "__SSE4_1__")  
            else()
                set_source_files_properties(${RNN_SOURCES_SSE4_1} PROPERTIES COMPILE_FLAGS -msse4.1)
            endif()
        endif()
    endif()
    if(AVX2_SUPPORTED)
        if(RNN_X86_MAY_HAVE_AVX2)
            if(MSVC)
                set_source_files_properties(${RNN_SOURCES_AVX2} PROPERTIES COMPILE_FLAGS "/arch:AVX2")
            else()
                set_source_files_properties(${RNN_SOURCES_AVX2} PROPERTIES COMPILE_FLAGS "-mavx -mavx2 -mfma")
            endif()
        endif()
    endif()
endif()

add_library(rnnoise STATIC ${RNNOISE_SOURCES})

target_include_directories(rnnoise PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/x86
    ${CMAKE_CURRENT_BINARY_DIR}/src
)
target_include_directories(rnnoise PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

if(RNN_X86_MAY_HAVE_SSE
   OR RNN_X86_MAY_HAVE_SSE2
   OR RNN_X86_MAY_HAVE_SSE4_1
   OR RNN_X86_MAY_HAVE_AVX2)
  target_compile_definitions(rnnoise PRIVATE OPUS_HAVE_RTCD)
endif()


if (RNN_ENABLE_X86_RTCD)
    if(RNN_X86_MAY_HAVE_SSE4_1 OR RNN_X86_MAY_HAVE_AVX2)
        target_compile_definitions(rnnoise PRIVATE RNN_ENABLE_X86_RTCD)
    endif()
endif()

if(SSE1_SUPPORTED)
    if(X86_PRESUME_SSE)
        if(MSVC)
            target_compile_options(rnnoise PRIVATE /arch:SSE)
        else()
            target_compile_options(rnnoise PRIVATE -msse)
        endif()
    endif()
endif()

if(SSE2_SUPPORTED)
    if(RNN_X86_MAY_HAVE_SSE2)
        if(MSVC)
            target_compile_options(rnnoise PRIVATE /arch:SSE2)
            target_compile_definitions(rnnoise PRIVATE OPUS_X86_MAY_HAVE_SSE2)
        else()
            target_compile_options(rnnoise PRIVATE -msse2)
        endif()
    endif()
endif()

if(COMPILER_SUPPORT_NEON AND RNN_USE_NEON)
  if(RNN_MAY_HAVE_NEON)
        if(RUNTIME_CPU_CAPABILITY_DETECTION)
            message(STATUS "RNN_MAY_HAVE_NEON enabling runtime detection for RNNoise")
            target_compile_definitions(opus PRIVATE OPUS_HAVE_RTCD)
        endif()
    endif()
endif()

if(MSVC)
    target_compile_options(rnnoise PRIVATE /wd4244 /wd4305)
endif()

if(ENABLE_SANITIZER)
    if(MSVC)
        target_compile_options(rnnoise PRIVATE /fsanitize=off)
        target_link_options(rnnoise PRIVATE /fsanitize=off)
    else()
        target_compile_options(rnnoise PRIVATE -fno-sanitize=all)
        target_link_options(rnnoise PRIVATE -fno-sanitize=all)
    endif()
endif()

set_target_properties(rnnoise PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    VERSION "${PROJECT_VERSION}"
    SOVERSION "1"
)

if(APPLE)
    if(IOS)
        target_link_libraries(rnnoise PRIVATE "-framework CoreFoundation")
    else()
        target_link_libraries(rnnoise PRIVATE "-framework CoreFoundation" "-framework CoreServices")
    endif()
endif()

install(TARGETS rnnoise
    EXPORT RNNoiseTargets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/include/rnnoise.h"
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(EXPORT RNNoiseTargets
    FILE RNNoiseTargets.cmake
    NAMESPACE RNNoise::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/RNNoise
)
