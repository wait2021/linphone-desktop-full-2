# This file is adapted from opus_functions.cmake file in Opus library.
 
function(get_library_version RNN_LIBRARY_VERSION RNN_LIBRARY_VERSION_MAJOR)
  file(STRINGS configure.ac opus_lt_current_string
       LIMIT_COUNT 1
       REGEX "OP_LT_CURRENT=")
  string(REGEX MATCH
               "OP_LT_CURRENT=([0-9]*)"
               _
               ${opus_lt_current_string})
  set(OP_LT_CURRENT ${CMAKE_MATCH_1})

  file(STRINGS configure.ac opus_lt_revision_string
       LIMIT_COUNT 1
       REGEX "OP_LT_REVISION=")
  string(REGEX MATCH
               "OP_LT_REVISION=([0-9]*)"
               _
               ${opus_lt_revision_string})
  set(OP_LT_REVISION ${CMAKE_MATCH_1})

  file(STRINGS configure.ac opus_lt_age_string
       LIMIT_COUNT 1
       REGEX "OP_LT_AGE=")
  string(REGEX MATCH
               "OP_LT_AGE=([0-9]*)"
               _
               ${opus_lt_age_string})
  set(OP_LT_AGE ${CMAKE_MATCH_1})

  math(EXPR RNN_LIBRARY_VERSION_MAJOR "${OP_LT_CURRENT} - ${OP_LT_AGE}")
  set(RNN_LIBRARY_VERSION_MINOR ${OP_LT_AGE})
  set(RNN_LIBRARY_VERSION_PATCH ${OP_LT_REVISION})
  set(
    RNN_LIBRARY_VERSION
    "${RNN_LIBRARY_VERSION_MAJOR}.${RNN_LIBRARY_VERSION_MINOR}.${RNN_LIBRARY_VERSION_PATCH}"
    PARENT_SCOPE)
  set(RNN_LIBRARY_VERSION_MAJOR ${RNN_LIBRARY_VERSION_MAJOR} PARENT_SCOPE)
endfunction()

function(get_package_version PACKAGE_VERSION)
  find_package(Git)
  if(GIT_FOUND)
    execute_process(COMMAND ${GIT_EXECUTABLE} describe --tags --match "v*"
                    OUTPUT_VARIABLE RNN_PACKAGE_VERSION)
    if(RNN_PACKAGE_VERSION)
      string(STRIP ${RNN_PACKAGE_VERSION}, RNN_PACKAGE_VERSION)
      string(REPLACE \n
                     ""
                     RNN_PACKAGE_VERSION
                     ${RNN_PACKAGE_VERSION})
      string(REPLACE ,
                     ""
                     RNN_PACKAGE_VERSION
                     ${RNN_PACKAGE_VERSION})

      string(SUBSTRING ${RNN_PACKAGE_VERSION}
                       1
                       -1
                       RNN_PACKAGE_VERSION)
      set(PACKAGE_VERSION ${RNN_PACKAGE_VERSION} PARENT_SCOPE)
      return()
    endif()
  endif()

  if(EXISTS "${CMAKE_SOURCE_DIR}/package_version")
    # Not a git repo, lets' try to parse it from package_version file if exists
    file(STRINGS package_version rnn_package_version_string
         LIMIT_COUNT 1
         REGEX "PACKAGE_VERSION=")
    string(REPLACE "PACKAGE_VERSION="
                   ""
                   rnn_package_version_string
                   ${rnn_package_version_string})
    string(REPLACE "\""
                   ""
                   rnn_package_version_string
                   ${rnn_package_version_string})
    set(PACKAGE_VERSION ${rnn_package_version_string} PARENT_SCOPE)
    return()
  endif()

  # if all else fails set to 0
  set(PACKAGE_VERSION 0 PARENT_SCOPE)
endfunction()

function(check_flag NAME FLAG)
  include(CheckCCompilerFlag)
  check_c_compiler_flag(${FLAG} ${NAME}_SUPPORTED)
endfunction()

include(CheckIncludeFile)
# function to check if compiler supports SSE, SSE2, SSE4.1 and AVX2 if target
# systems may not have SSE support then use RNN_MAY_HAVE_SSE option if target
# system is guaranteed to have SSE support then RNN_PRESUME_SSE can be used to
# skip SSE runtime check
function(rnnoise_detect_sse COMPILER_SUPPORT_SIMD)
  message(STATUS "Check SIMD support by compiler")
  check_include_file(xmmintrin.h HAVE_XMMINTRIN_H) # SSE1
  if(HAVE_XMMINTRIN_H)
    if(MSVC)
      # different arch options for 32 and 64 bit target for MSVC
      if(CMAKE_SIZEOF_VOID_P EQUAL 4)
        check_flag(SSE1 /arch:SSE)
      else()
        set(SSE1_SUPPORTED 1 PARENT_SCOPE)
      endif()
    else()
      check_flag(SSE1 -msse)
    endif()
  else()
    set(SSE1_SUPPORTED 0 PARENT_SCOPE)
  endif()

  check_include_file(emmintrin.h HAVE_EMMINTRIN_H) # SSE2
  if(HAVE_EMMINTRIN_H)
    if(MSVC)
      if(CMAKE_SIZEOF_VOID_P EQUAL 4)
        check_flag(SSE2 /arch:SSE2)
      else()
        set(SSE2_SUPPORTED 1 PARENT_SCOPE)
      endif()
    else()
      check_flag(SSE2 -msse2)
    endif()
  else()
    set(SSE2_SUPPORTED 0 PARENT_SCOPE)
  endif()

  check_include_file(smmintrin.h HAVE_SMMINTRIN_H) # SSE4.1
  if(HAVE_SMMINTRIN_H)
    if(MSVC)
      if(CMAKE_SIZEOF_VOID_P EQUAL 4)
        check_flag(SSE4_1 /arch:SSE2) # SSE2 and above
      else()
        set(SSE4_1_SUPPORTED 1 PARENT_SCOPE)
      endif()
    else()
      check_flag(SSE4_1 -msse4.1)
    endif()
  else()
    set(SSE4_1_SUPPORTED 0 PARENT_SCOPE)
  endif()

  check_include_file(immintrin.h HAVE_IMMINTRIN_H) # AVX2
  if(HAVE_IMMINTRIN_H)
    if(MSVC)
      check_flag(AVX2 /arch:AVX2)
    else()
      check_flag(AVX2 -mavx2)
    endif()
  else()
    set(AVX2_SUPPORTED 0 PARENT_SCOPE)
  endif()

  if(SSE1_SUPPORTED OR SSE2_SUPPORTED OR SSE4_1_SUPPORTED OR AVX2_SUPPORTED)
    set(COMPILER_SUPPORT_SIMD 1 PARENT_SCOPE)
  else()
    message(STATUS "No SIMD support in compiler")
  endif()
endfunction()

function(rnnoise_detect_neon COMPILER_SUPPORT_NEON)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "(armv7|armv7-a|armv7s|aarch64|arm64)")
    message(STATUS "Check NEON support by compiler")
    check_include_file(arm_neon.h HAVE_ARM_NEON_H)
    if(HAVE_ARM_NEON_H)
      set(COMPILER_SUPPORT_NEON ${HAVE_ARM_NEON_H} PARENT_SCOPE)
    endif()
  endif()
endfunction()

function(rnnoise_supports_cpu_detection RUNTIME_CPU_CAPABILITY_DETECTION)
  if(MSVC)
    check_include_file(intrin.h HAVE_INTRIN_H)
  else()
    check_include_file(cpuid.h HAVE_CPUID_H)
  endif()
  if(HAVE_INTRIN_H OR HAVE_CPUID_H)
    set(RUNTIME_CPU_CAPABILITY_DETECTION 1 PARENT_SCOPE)
  elseif(CMAKE_SYSTEM_NAME MATCHES "(Linux|Android)")
  #Linux and Android have /proc/cpuinfo.
    set(RUNTIME_CPU_CAPABILITY_DETECTION 1 PARENT_SCOPE)
  else()
    set(RUNTIME_CPU_CAPABILITY_DETECTION 0 PARENT_SCOPE)
  endif()
endfunction()
