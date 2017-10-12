gconnect_conf = configuration_data()
gconnect_conf.set_quoted('GETTEXT_PACKAGE', meson.project_name(),
                  description: 'Gettext Package')
gconnect_conf.set_quoted('PACKAGE_NAME', meson.project_name(),
                  description: 'Define to the name of this package.')
gconnect_conf.set_quoted('PACKAGE_DESCRIPTION', short_description,
                  description: 'Define to a short description of this package.')
gconnect_conf.set_quoted('PACKAGE_URL', project_web,
                  description: 'Define to the home page for this package.')
gconnect_conf.set_quoted('PACKAGE_BUGREPORT', project_bugs,
                  description: 'Define to the address where bug reports for this package should be sent.')
gconnect_conf.set_quoted('PACKAGE_API_VERSION', api_version,
                  description: 'Define to the API version of this package.')
gconnect_conf.set_quoted('PACKAGE_VERSION', meson.project_version(),
                  description: 'Define to the version of this package.')
gconnect_conf.set_quoted('VERSION', meson.project_version(),
                  description: 'Version number of package')
gconnect_conf.set_quoted('PACKAGE_DATADIR', join_paths(get_option('prefix'), get_option('datadir')),
                  description: 'Define to datadir of this package.')
gconnect_conf.set_quoted('PACKAGE_LOCALEDIR', join_paths(get_option('prefix'), get_option('datadir'), 'locale'),
                  description: 'Define to locale dir of this package.')
gconnect_conf.set_quoted('PACKAGE_PLUGINSDIR', join_paths(get_option('prefix'), plugin_subdir), 
                  description: 'Define to plugins dir of this package.')
gconnect_conf.set_quoted('SETTINGS_PATH', '/apps/gconnect/',
                  description: 'Define to root path of gsettings for this package.')
gconnect_conf.set_quoted('SETTINGS_NAME', 'org.gconnect',
                  description: 'Define to root bus name for this package.')

configure_file(output: 'gconnect-config.vala',
               input: 'gconnect-config.vala.in',
               configuration: gconnect_conf)
