# FindGObjectIntrospection.cmake
# © 2016 Evan Nemerson <evan@nemerson.com>

find_program(GI_COMPILER_EXECUTABLE g-ir-compiler)
find_program(GI_SCANNER_EXECUTABLE g-ir-scanner)

if(CMAKE_INSTALL_FULL_DATADIR)
  set(GI_REPOSITORY_DIR "${CMAKE_INSTALL_FULL_DATADIR}/gir-1.0")
else()
  set(GI_REPOSITORY_DIR "${CMAKE_INSTALL_PREFIX}/share/gir-1.0")
endif()

if(CMAKE_INSTALL_FULL_LIBDIR)
  set(GI_TYPELIB_DIR "${CMAKE_INSTALL_FULL_LIBDIR}/girepository-1.0")
else()
  set(GI_TYPELIB_DIR "${CMAKE_INSTALL_LIBDIR}/girepository-1.0")
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(GObjectIntrospection
  REQUIRED_VARS
    GI_COMPILER_EXECUTABLE
    GI_SCANNER_EXECUTABLE)

function(gobject_introspection_compile TYPELIB)
  set (options DEBUG VERBOSE)
  set (oneValueArgs MODULE SHARED_LIBRARY)
  set (multiValueArgs FLAGS INCLUDE_DIRS)
  cmake_parse_arguments(GI_COMPILER "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  unset (options)
  unset (oneValueArgs)
  unset (multiValueArgs)

  get_filename_component(TYPELIB "${TYPELIB}" ABSOLUTE
    BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}")

  if(GI_COMPILER_DEBUG)
    list(APPEND GI_COMPILER_FLAGS "--debug")
  endif()

  if(GI_COMPILER_VERBOSE)
    list(APPEND GI_COMPILER_FLAGS "--verbose")
  endif()

  if(GI_SHARED_LIBRARY)
    list(APPEND GI_COMPILER_FLAGS "--shared-library" "${GI_SHARED_LIBRARY}")
  endif()

  foreach(include_dir ${GI_COMPILER_INCLUDE_DIRS})
    list(APPEND GI_COMPILER_FLAGS "--includedir" "${include_dir}")
  endforeach()

  add_custom_command(
    OUTPUT "${TYPELIB}"
    COMMAND "${GI_COMPILER_EXECUTABLE}"
    ARGS
      "-o" "${TYPELIB}"
      ${GI_COMPILER_FLAGS}
      ${GI_COMPILER_UNPARSED_ARGUMENTS}
    DEPENDS
      ${GI_COMPILER_UNPARSED_ARGUMENTS})
endfunction()
