# compile_plugin(
#   PLUGIN_FILES
#   NAME plugin_name
#   TYPE plugin_type
#   SOURCES plugin.vala
#   [GSETTINGS plugin.gschema.xml]
#   [VALA_PACKAGES …]
# )
#
# This function will compile the plugin
#
# This function checks the plugin type and compiles it if necessary.
#
# Options:
#
#   PLUGIN_FILES
#     Variable in which to store the list of generated sources (which
#     you should pass to install).
#   NAME plugin_name
#     The name of the plugin.
#   TYPE plugin_type
#     Type of plugin, can be "vala" or "python".
#     If "python", there is no compilation and PLUGIN_FILES=SOURCES
#     If "vala", SOURCES are compiled to a shared library "libplugin_name.so"
#   SOURCES plugin.vala
#     Can be plugin.vala or plugin.py or a list of files
#   GSETTINGS plugin.gschema.xml
#     Includes a Gsettings file
#   FLAGS ...
#     Add the flags for valac to VALA_COMPILER_FLAGS
#   VALA_PACKAGES
#     Vala packages dependencies
macro(compile_plugin PLUGIN_FILES)
    set (options)
    set (oneValueArgs TYPE NAME GSETTINGS)
    set (multiValueArgs SOURCES VALA_PACKAGES)
    cmake_parse_arguments(PLUGIN "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    unset (options)
    unset (oneValueArgs)
    unset (multiValueArgs)

    #list(APPEND PLUGIN_SOURCES
        #../helper.vala)

    if("${PLUGIN_TYPE}" STREQUAL "vala")
        set(PLUGIN_C_SOURCES)
        # Compile Vala sources to C
        vala_precompile_target(
            "${PLUGIN_NAME}-vala"
            PLUGIN_C_SOURCES
            ${CMAKE_BINARY_DIR}/lib/gconnect-${GCONNECT_VERSION_API}.vapi
            ${PLUGIN_SOURCES}
            PACKAGES ${PLUGIN_VALA_PACKAGES}
            DEPENDS "${GCONNECT_LIBRARY_NAME}-vala"
        )

        if(PLUGIN_GSETTINGS)
            #GSettings
            include(GSettings)
            add_schema("${PLUGIN_GSETTINGS}")
        endif(PLUGIN_GSETTINGS)

        # Compile the library.
        add_library(${PLUGIN_NAME}
            SHARED
            ${PLUGIN_C_SOURCES})
        # Make sure the Vala sources are compiled to C before attempting to
        # build the library.
        add_dependencies("${PLUGIN_NAME}" "${PLUGIN_NAME}-vala")


        set(${PLUGIN_FILES}
            "${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}${PLUGIN_NAME}${CMAKE_SHARED_LIBRARY_SUFFIX}")

        # Generate a .gitignore
        file(WRITE  ".gitignore" "# Automatically generated by CMake, do not modify.\n")
        foreach(file
                ".gitignore"
                "${CMAKE_SHARED_LIBRARY_PREFIX}${PLUGIN_NAME}${CMAKE_SHARED_LIBRARY_SUFFIX}*")
            file(APPEND ".gitignore" "/${file}\n")
        endforeach(file)
        foreach(file ${PLUGIN_C_SOURCES})
            string(REPLACE "${CMAKE_CURRENT_BINARY_DIR}/" "" file ${file})
            file(APPEND ".gitignore" "/${file}\n")
        endforeach(file)

        unset(PLUGIN_C_SOURCES)
    elseif("${PLUGIN_TYPE}" STREQUAL "py" OR "${PLUGIN_TYPE}" STREQUAL "python" )
        set(${PLUGIN_FILES} ${PLUGIN_SOURCES})

    endif("${PLUGIN_TYPE}" STREQUAL "vala")
    
    unset(PLUGIN_GSETTINGS)
    unset(PLUGIN_VALA_PACKAGES)
    unset(PLUGIN_SOURCES)
    unset(PLUGIN_TYPE)
endmacro()


