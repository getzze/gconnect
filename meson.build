project('gconnect', 'vala', 'c',
    version : '0.1.0',
    license : 'GPLv3')


# Project web site
project_web = 'https://github.com/getzze/gconnect'
# Where to report bugs; usually either an e-mail address or an issue
# tracker URL.
project_bugs = 'https://github.com/getzze/gconnect/issues'

short_description = 'KDEConnect protocol implementation in Vala'

as_version = meson.project_version() # set in project() below
ver_arr = as_version.split('.')

as_major_version = ver_arr[0]
as_minor_version = ver_arr[1]
as_micro_version = ver_arr[2]

# API version.
#
# This will go in the pkg-config and shared library names.  Should
# only be changed if the API breaks backwards compatibility.
api_version = '0.1'

meson_dir = meson.current_source_dir()

add_project_arguments(['--vapidir',
                       join_paths(meson.current_source_dir(), 'vapi')],
                      language: 'vala')


add_project_arguments('--enable-checking', language : 'vala')
add_project_arguments('-DGETTEXT_PACKAGE="@0@"'.format(meson.project_name()), language : 'c')
buildtype = get_option('buildtype')
if buildtype.startswith('debug')
    message('Build type: @0@'.format(buildtype))
    add_global_arguments('--define=DEBUG_BUILD', language : 'vala')
endif

# The subdir where plugin files should be installed, with respect to prefix
plugin_subdir = join_paths(get_option('datadir'), meson.project_name(), 'plugins')

# The name of the shared library.  Note that a "lib" prefix will be
# added automatically on systems where that is the convention.
package_name = meson.project_name() + '-' + api_version

# Name of the GObject Introspection repository for the library.
gir_name = 'Gconnect-' + api_version

doc_subdir = join_paths(get_option('datadir'), 'doc', meson.project_name())
install_data('HISTORY.md', 'README.md',
    install_dir: doc_subdir)

licenses_subdir = join_paths(get_option('datadir'), 'licenses', meson.project_name())
install_data('COPYING',
    install_dir: licenses_subdir)

subdir('lib')
subdir('daemon')
subdir('plugins')
xgettext = find_program('xgettext', required : false)
if xgettext.found()
  subdir('po')
endif

if get_option('documentation')
  valadoc = find_program('valadoc', required: false)
  if valadoc.found()
#     subdir('doc')
  endif
endif

if get_option('test')
  check_dep = dependency('check')
#   subdir('tests')
endif

# subdir('cli')
# subdir('gui')




