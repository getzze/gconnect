#
#
# Library Target: linked against executable and tests.

subdir('conf')
                  
# dependencies
lib_deps = [
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gio-2.0'),
  dependency('json-glib-1.0'),
  dependency('gee-0.8'),
  dependency('libpeas-1.0'),
  dependency('gnutls'),
  meson.get_compiler('vala').find_library('posix'),
  dependency('uuid'),
  dependency('gnutls'),
]

vala_args = []
vala_src = [
  join_paths(meson.current_build_dir(), 'conf', 'gconnect-config.vala'),
  'config.vala',
  'packet.vala',
  'pluginmanager.vala',
  'devicemanager.vala',
  'connection.vala',
  'channels/loopback/loopbackconnection.vala',
  'core.vala',
  'crypt/certificate.vala',
  'crypt/crypt.c',
  'crypt/crypt.vapi',
]

has_lan = get_option('gconnect_lan')
if has_lan
  ## Add Lan provider
  vala_args += ['--define=GCONNECT_LAN']
  vala_src += [
    'channels/lan/lanlinkprovider.vala',
    'channels/lan/landevicelink.vala',
    'channels/lan/lanconfig.vala',
  ]
endif

gconnect_lib = shared_library(package_name, vala_src,
                              dependencies : lib_deps,
                              vala_args: vala_args,
                              vala_gir: gir_name + '.gir',
                              install: true,
                              install_dir: [true, true, true, true])

g_ir_compiler = find_program('g-ir-compiler')
custom_target('typelib', command: [g_ir_compiler, '--shared-library', gconnect_lib.full_path(), '--output', '@OUTPUT@', join_paths(meson.current_build_dir(), gir_name + '.gir')],
              output: gir_name + '.typelib',
              depends: gconnect_lib,
              install: true,
              install_dir: join_paths(get_option('libdir'), 'girepository-1.0'))


gconnect_dep = declare_dependency(
  include_directories: include_directories('.'),
  link_with: gconnect_lib)

#GSettings
install_data('gconnect.gschema.xml', install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas'))
install_data('channels/lan/gconnect.lan.gschema.xml', install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas'))
meson.add_install_script(join_paths(meson_dir, 'meson_post_install.py'))

## Uncomment if external dependencies are required
## Any dependencies that appear in the library vapi
## they should be included in the .deps file
#set(GCONNECT_VALA_EXTERN_PACKAGES)
## Write list of dependency file (Makefile style)
#file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/${GCONNECT_PKG_NAME}.deps" "" )
#foreach(var ${GCONNECT_VALA_EXTERN_PACKAGES})
    #file(APPEND "${CMAKE_CURRENT_BINARY_DIR}/${GCONNECT_PKG_NAME}.deps"
        #"${var}\n")
#endforeach(var)

# Generate and install a pkg-config file
pkg = import('pkgconfig')
pkg.generate(
  libraries: gconnect_lib,
  filebase: package_name,
  name: meson.project_name(),
  version: meson.project_version(),
  description: short_description,
  variables: [
    'datarootdir=${prefix}/'+join_paths(get_option('datadir')),
    'datadir=${datarootdir}',
  ],
)
