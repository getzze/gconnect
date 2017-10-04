#
#
# Main target

# Plugin type
set(plugin_type "vala")
set(plugin_name "findmyphone")

set(plugin_files
    "${plugin_name}.plugin")

set(plugin_sources
    "${plugin_name}.${plugin_type}")

set(plugin_vala_packages
    ${GCONNECT_PROJECT_VALA_PACKAGES})

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

unset(plugin_files_compiled)
unset(plugin_gsettings)
unset(plugin_vala_packages)
unset(plugin_sources)
unset(plugin_files)
unset(plugin_type)
