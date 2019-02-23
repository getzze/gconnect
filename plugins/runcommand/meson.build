# Plugin type

name = 'RunCommand'
file = name.to_lower()
conf = configuration_data()
conf.set('file', file)
conf.set('name', name)
conf.set('desc', 'Execute console commands remotely')
conf.set('outcap', 'kdeconnect.runcommand')
conf.set('incap', 'kdeconnect.runcommand.request')
configure_file(input: plugins_template,
               output: file + '.plugin',
               install_dir: join_paths(plugin_subdir, file),
               configuration: conf)

plugin_source = file + '.vala'
plugin_deps = [
  plugins_deps,
#   dependency('threads'),
]

plugin_mod = shared_module(
  file,
  plugin_source,
  dependencies : plugin_deps,
#   vala_args: '--thread',
  install: true,
  install_dir: [join_paths(plugin_subdir, file), false, false],
)

#GSettings
install_data('gconnect.' + file + '.gschema.xml', install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas'))
