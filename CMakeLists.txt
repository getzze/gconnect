project("gconnect" C)
cmake_minimum_required(VERSION 3.2)

# Project web site
set(PROJECT_WEB "https://github.com/getzze/gconnect")
# Where to report bugs; usually either an e-mail address or an issue
# tracker URL.
set(PROJECT_BUGS "https://github.com/getzze/gconnect/issues")
# Gettext package name
set(GETTEXT_PACKAGE ${PROJECT_NAME})

# Library version
#
# This should be incremented with every release.  See semver.org.
set (GCONNECT_VERSION_MAJOR    0)
set (GCONNECT_VERSION_MINOR    1)
set (GCONNECT_VERSION_REVISION 0)

# API version.
#
# This will go in the pkg-config and shared library names.  Should
# only be changed if the API breaks backwards compatibility.
set (GCONNECT_VERSION_API      "0.1")

# ABI version
#
# Rules from § 11.4: Library Versioning of the autobook
# https://www.sourceware.org/autobook/autobook/autobook_61.html
#
# 1) If you have changed any of the sources for this library, the
#    revision number must be incremented. This is a new revision of
#    the current interface.
# 2) If the interface has changed, then current must be incremented,
#    and revision reset to ‘0’. This is the first revision of a new
#    interface.
# 3) If the new interface is a superset of the previous interface
#    (that is, if the previous interface has not been broken by the
#    changes in this new release), then age must be incremented. This
#    release is backwards compatible with the previous release.
# 4) If the new interface has removed elements with respect to the
#    previous interface, then you have broken backward compatibility
#    and age must be reset to ‘0’. This release has a new, but
#    backwards incompatible interface.
#
# Conveniently, this also matches semantic versioning for the most
# part (API changes are a bit more complicated since we change the
# library and pkg-config names and can reset these to whatever we
# want, but we don't *have* to.
set (GCONNECT_SOVERSION_CURRENT  ${GCONNECT_VERSION_MAJOR})
set (GCONNECT_SOVERSION_REVISION ${GCONNECT_VERSION_MINOR})
set (GCONNECT_SOVERSION_AGE      ${GCONNECT_VERSION_REVISION})

include(GNUInstallDirs)

enable_testing()

list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)

# This creates a "dist" target which will generate a release tarball
# for your project.
set(CPACK_SOURCE_GENERATOR "TBZ2")
set(CPACK_SOURCE_PACKAGE_FILE_NAME
  "${CMAKE_PROJECT_NAME}-${GCONNECT_VERSION_MAJOR}.${GCONNECT_VERSION_MINOR}.${GCONNECT_VERSION_REVISION}")
set(CPACK_SOURCE_IGNORE_FILES
  "/build/;/.git/;/.bzr/;~$;${CPACK_SOURCE_IGNORE_FILES}")
include(CPack)
add_custom_target(dist COMMAND ${CMAKE_MAKE_PROGRAM} package_source)

find_package(GLib "2.38" REQUIRED)
find_package(Vala "0.30" REQUIRED)

find_package(PkgConfig)
pkg_check_modules(REQ_DEPS REQUIRED
    gobject-2.0
    gio-2.0
    #gthread-2.0
    gee-0.8
    json-glib-1.0
    libpeas-1.0
    gnutls
)
pkg_check_modules(OPT_DEPS REQUIRED
    openssl
)

include_directories(
    ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}
    ${REQ_DEPS_INCLUDE_DIRS}
    ${OPT_DEPS_INCLUDE_DIRS}
)

add_definitions(
    ${REQ_DEPS_CFLAGS} ${REQ_DEPS_CFLAGS_OTHER}
    ${OPT_DEPS_CFLAGS} ${OPT_DEPS_CFLAGS_OTHER}
)

link_libraries(
    ${REQ_DEPS_LIBRARIES}
    ${OPT_DEPS_LIBRARIES})

link_directories(
    ${REQ_DEPS_LIBRARY_DIRS}
    ${OPT_DEPS_LIBRARY_DIRS})

# If someone doesn't specify a build type, default to "Debug"
if(CMAKE_BUILD_TYPE STREQUAL "")
  set(CMAKE_BUILD_TYPE "Debug")
endif(CMAKE_BUILD_TYPE STREQUAL "")

if (CMAKE_BUILD_TYPE MATCHES "Debug")
    message(STATUS "Build of debug type")
endif (CMAKE_BUILD_TYPE MATCHES "Debug")


list(APPEND VALA_COMPILER_FLAGS "--target-glib=2.38")
list(APPEND VALA_COMPILER_FLAGS_DEBUG "--debug")
#list(APPEND VALA_COMPILER_FLAGS_DEBUG "--enable-mem-profiler")
list(APPEND VALA_COMPILER_FLAGS_DEBUG "--enable-checking")
list(APPEND VALA_COMPILER_FLAGS_DEBUG "--define=DEBUG_BUILD")

# Lots of perfectly valid Vala code will trigger warnings from the C
# compiler, almost always false-positives.  This often drowns out
# legitimate warnings, so we'll try to disable them here.
include(AddCompilerFlags)
global_add_compiler_flags(-Wno-incompatible-pointer-types)

## Add code covergae with gcovr
#include(CodeCoverage)
#APPEND_COVERAGE_COMPILER_FLAGS("-O0 -fprofile-arcs -ftest-coverage")

# Uninstall target
configure_file (
    "${CMAKE_SOURCE_DIR}/cmake/Uninstall.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
    IMMEDIATE @ONLY)

add_custom_target (uninstall
    COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake)


# The name of the shared library.  Note that a "lib" prefix will be
# added automatically on systems where that is the convention.
set(GCONNECT_LIBRARY_NAME ${PROJECT_NAME}-${GCONNECT_VERSION_API})

# The name of the VAPI to generate, which also needs to be the
# pkg-config name.  It's often a good idea to make this the same as
# your shared library name, but not required.  For example, if your
# project is called "libfoo" you should have your library be named
# "foo", but use "libfoo" for the package name.
#
# For our example, we'll use the project name (which we set at the
# beginning of the top level CMakeLists.txt.
set(GCONNECT_PKG_NAME ${PROJECT_NAME}-${GCONNECT_VERSION_API})

# Name of the GObject Introspection repository for the library.
set(GCONNECT_GIR_NAME "Gconnect-${GCONNECT_VERSION_API}")

# The path where libraries files should be searched for
set(LIBRARY_PATH "lib")

# The subdir where plugin files should be installed
set(GCONNECT_PLUGIN_SUBDIR "${PROJECT_NAME}/plugins/")

# The subdir where plugin files should be installed
set(GCONNECT_CUSTOM_VAPIS "${CMAKE_SOURCE_DIR}/vapis")

include(CompilePlugin)

#add_subdirectory(lib/crypt)
add_subdirectory(lib)
add_subdirectory(daemon)
#add_subdirectory(cli)
#add_subdirectory(gui)
#add_subdirectory(tests)
add_subdirectory(po)
add_subdirectory(plugins)
