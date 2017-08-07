# Copyright (c) 2016 Evan Nemerson <evan@nemerson.com>
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# This module provides a convenient way to add C/C++ compiler flags if
# the compiler supports them.

include (CheckCCompilerFlag)
include (CheckCXXCompilerFlag)

# Depending on the settings, some compilers will accept unknown flags.
# We try to disable this behavior by also passing these flags when we
# check if a flag is supported.
set (ADD_COMPILER_FLAGS_PREPEND "")

if ("GNU" STREQUAL "${CMAKE_C_COMPILER_ID}")
  set (ADD_COMPILER_FLAGS_PREPEND "-Wall -Wextra -Werror")
elseif ("Clang" STREQUAL "${CMAKE_C_COMPILER_ID}")
  set (ADD_COMPILER_FLAGS_PREPEND "-Werror=unknown-warning-option")
endif ()

##
# Set a variable to different flags, depending on which compiler is in
# use.
#
# Example:
#   set_compiler_flags(VARIABLE varname MSVC /wd666 INTEL /wd1729)
#
#   This will set varname to /wd666 if the compiler is MSVC, and /wd1729
#   if it is Intel.
#
# Possible compilers:
#  - GCC: GNU C Compiler
#  - GCCISH: A compiler that (tries to) be GCC-compatible on the CLI
#    (i.e., anything but MSVC).
#  - CLANG: clang
#  - MSVC: Microsoft Visual C++ compiler
#  - INTEL: Intel C Compiler
#
# Note: the compiler is determined based on the value of the
# CMAKE_C_COMPILER_ID variable, not CMAKE_CXX_COMPILER_ID.
##
function (set_compiler_specific_flags)
  set (oneValueArgs VARIABLE)
  set (multiValueArgs GCC GCCISH INTEL CLANG MSVC)
  cmake_parse_arguments(COMPILER_SPECIFIC_FLAGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  unset (options)
  unset (oneValueArgs)
  unset (multiValueArgs)

  set (compiler_flags)

  if ("${CMAKE_C_COMPILER_ID}" STREQUAL "GNU")
    list (APPEND compiler_flags ${COMPILER_SPECIFIC_FLAGS_GCC})
  elseif("${CMAKE_C_COMPILER_ID}" STREQUAL "Clang")
    list (APPEND compiler_flags ${COMPILER_SPECIFIC_FLAGS_CLANG})
  elseif("${CMAKE_C_COMPILER_ID}" STREQUAL "Intel")
    list (APPEND compiler_flags ${COMPILER_SPECIFIC_FLAGS_INTEL})
  elseif("${CMAKE_C_COMPILER_ID}" STREQUAL "MSVC")
    list (APPEND compiler_flags ${COMPILER_SPECIFIC_FLAGS_MSVC})
  endif()

  if (NOT "${CMAKE_C_COMPILER_ID}" STREQUAL "MSVC")
    list (APPEND compiler_flags ${COMPILER_SPECIFIC_FLAGS_GCCISH})
  endif ()

  set (${COMPILER_SPECIFIC_FLAGS_VARIABLE} "${compiler_flags}" PARENT_SCOPE)
endfunction ()

function (source_file_add_compiler_flags_unchecked file)
  set (flags ${ARGV})
  list (REMOVE_AT flags 0)
  get_source_file_property (sources ${file} SOURCES)

  foreach (flag ${flags})
    get_source_file_property (existing ${file} COMPILE_FLAGS)
    if ("${existing}" STREQUAL "NOTFOUND")
      set_source_files_properties (${file}
        PROPERTIES COMPILE_FLAGS "${flag}")
    else ()
      set_source_files_properties (${file}
        PROPERTIES COMPILE_FLAGS "${existing} ${flag}")
    endif ()
  endforeach (flag)
endfunction ()

function (source_file_add_compiler_flags file)
  set (flags ${ARGV})
  list (REMOVE_AT flags 0)
  get_source_file_property (sources ${file} SOURCES)

  foreach (flag ${flags})
    if ("GNU" STREQUAL "${CMAKE_C_COMPILER_ID}")
      # Because https://gcc.gnu.org/wiki/FAQ#wnowarning
      string (REGEX REPLACE "\\-Wno\\-(.+)" "-W\\1" flag_to_test "${flag}")
    else ()
      set (flag_to_test ${flag})
    endif ()

    if ("${file}" MATCHES "\\.c$")
      string (REGEX REPLACE "[^a-zA-Z0-9]+" "_" test_name "CFLAG_${flag_to_test}")
      CHECK_C_COMPILER_FLAG ("${ADD_COMPILER_FLAGS_PREPEND} ${flag_to_test}" ${test_name})
    elseif ("${file}" MATCHES "\\.(cpp|cc|cxx)$")
      string (REGEX REPLACE "[^a-zA-Z0-9]+" "_" test_name "CXXFLAG_${flag_to_test}")
      CHECK_CXX_COMPILER_FLAG ("${ADD_COMPILER_FLAGS_PREPEND} ${flag_to_test}" ${test_name})
    endif ()

    if (${test_name})
      source_file_add_compiler_flags_unchecked (${file} ${flag})
    endif ()

    unset (test_name)
    unset (flag_to_test)
  endforeach (flag)

  unset (flags)
endfunction ()

function (target_add_compiler_flags target)
  set (flags ${ARGV})
  list (REMOVE_AT flags 0)
  get_target_property (sources ${target} SOURCES)

  foreach (source ${sources})
    source_file_add_compiler_flags (${source} ${flags})
  endforeach (source)

  unset (flags)
  unset (sources)
endfunction (target_add_compiler_flags)

# global_add_compiler_flags (flag1 [flag2 [flag3 ...]]):
#
# This just adds the requested compiler flags to
# CMAKE_C/CXX_FLAGS variable if they work with the compiler.
function (global_add_compiler_flags)
  set (flags ${ARGV})

  foreach (flag ${flags})
    if ("GNU" STREQUAL "${CMAKE_C_COMPILER_ID}")
      # Because https://gcc.gnu.org/wiki/FAQ#wnowarning
      string (REGEX REPLACE "\\-Wno\\-(.+)" "-W\\1" flag_to_test "${flag}")
    else ()
      set (flag_to_test "${flag}")
    endif ()

    string (REGEX REPLACE "[^a-zA-Z0-9]+" "_" c_test_name "CFLAG_${flag_to_test}")
    CHECK_C_COMPILER_FLAG ("${ADD_COMPILER_FLAGS_PREPEND} ${flag_to_test}" ${c_test_name})
    if (${c_test_name})
      set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${flag}")
    endif ()
    unset (c_test_name)

    string (REGEX REPLACE "[^a-zA-Z0-9]+" "_" cxx_test_name "CFLAG_${flag_to_test}")
    CHECK_CXX_COMPILER_FLAG ("${ADD_COMPILER_FLAGS_PREPEND} ${flag_to_test}" ${cxx_test_name})
    if (${cxx_test_name})
      set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${flag}")
    endif ()
    unset (cxx_test_name)

    unset (flag_to_test)
  endforeach (flag)

  unset (flags)

  set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS}" PARENT_SCOPE)
  set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}" PARENT_SCOPE)
endfunction (global_add_compiler_flags)
