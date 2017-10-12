# Plugin type

name = 'Findmyphone'
file = name.to_lower()
conf = configuration_data()
conf.set('file', file)
conf.set('name', name)
conf.set('desc', 'Find your lost phone by making it play an alarm sound')
conf.set('outcap', 'kdeconnect.findmyphone.request')
conf.set('incap', '')
configure_file(input: plugins_template,
               output: file + '.plugin',
               install_dir: join_paths(plugin_subdir, file),
               configuration: conf)

plugin_source = file + '.vala'
plugin_deps = [
  plugins_deps,
]

plugin_mod = shared_module(
  file,
  plugin_source,
  dependencies : plugin_deps,
  install: true,
  install_dir: [join_paths(plugin_subdir, file), false, false],
)
