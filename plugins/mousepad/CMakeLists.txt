#
#
# Main target

# Plugin type
set(plugin_type "vala")
set(plugin_name "mousepad")

set(plugin_files
    "${plugin_name}.plugin")

set(plugin_sources
    ${GCONNECT_CUSTOM_VAPIS}/xtst.vapi
    "${plugin_name}.${plugin_type}")

#pkg_check_modules(PLUGIN_DEPS REQUIRED gtk+-3.0 x11 xtst caribou-1.0)
pkg_check_modules(PLUGIN_DEPS REQUIRED gtk+-3.0 x11 caribou-1.0)
include_directories(${CMAKE_RUNTIME_OUTPUT_DIRECTORY} ${PLUGIN_DEPS_INCLUDE_DIRS})
add_definitions(${PLUGIN_DEPS_CFLAGS} ${PLUGIN_DEPS_CFLAGS_OTHER})
link_libraries(${PLUGIN_DEPS_LIBRARIES})
link_directories(${PLUGIN_DEPS_LIBRARY_DIRS})

set(plugin_vala_packages
    ${GCONNECT_PROJECT_VALA_PACKAGES}
    #xtst
    caribou-1.0
    gdk-x11-3.0
    gtk+-3.0
    gdk-3.0)

#set(plugin_gsettings)

compile_plugin(plugin_files_compiled
    TYPE ${plugin_type}
    NAME ${plugin_name}
    SOURCES ${plugin_sources}
    VALA_PACKAGES ${plugin_vala_packages})

list(APPEND plugin_files
    ${plugin_files_compiled})

# Install the plugins.
install (FILES ${plugin_files}
    DESTINATION ${CMAKE_INSTALL_DATADIR}/${GCONNECT_PLUGIN_SUBDIR}/${plugin_name})

unset(PLUGIN_DEPS)
unset(plugin_files_compiled)
unset(plugin_gsettings)
unset(plugin_vala_packages)
unset(plugin_sources)
unset(plugin_files)
unset(plugin_type)
