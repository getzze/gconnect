#
#
# Main target

# Any dependencies.  Note that it isn't actually necessary to add
# glib-2.0 or gobject-2.0 (it is done implicitly), but for this
# template project we don't actually depend on anything else, so we
# added it for illustrative purposes.
set(DEPS_FILE "${CMAKE_BINARY_DIR}/lib/gconnect-${GCONNECT_VERSION_API}.deps")
if(EXISTS "${DEPS_FILE}")
    file(STRINGS 
        "${DEPS_FILE}"      
        GCONNECT_PROJECT_VALA_PACKAGES)
else()
    set(GCONNECT_PROJECT_VALA_PACKAGES)
endif()

list(APPEND GCONNECT_PROJECT_VALA_PACKAGES
    json-glib-1.0
    libpeas-1.0)

# Subdirectories with the plugin files
set(GCONNECT_PLUGIN_LIST
    battery
    ping
    telephony
    clipboard
    mousepad
    findmyphone
    runcommand
)


foreach(subdir ${GCONNECT_PLUGIN_LIST})
    add_subdirectory(${subdir})
endforeach()

set(PLUGIN_HELPER
    helper.py
    __init__.py)


# Install the plugin python helper file.
install (FILES ${PLUGIN_HELPER}
    DESTINATION ${CMAKE_INSTALL_DATADIR}/${GCONNECT_PLUGIN_SUBDIR})
