# Plugin type

name = 'Battery'
file = name.to_lower()
conf = configuration_data()
conf.set('file', file)
conf.set('name', name)
conf.set('desc', 'Show device battery information')
conf.set('outcap', 'kdeconnect.battery.request')
conf.set('incap', 'kdeconnect.battery')
configure_file(input: plugins_template,
               output: file + '.plugin',
               install_dir: join_paths(plugin_subdir, file),
               configuration: conf)

plugin_source = file + '.vala'
plugin_deps = [
  plugins_deps,
  dependency('libnotify'),
]

plugin_mod = shared_module(
  file,
  plugin_source,
  dependencies : plugin_deps,
  install: true,
  install_dir: [join_paths(plugin_subdir, file), false, false],
)
