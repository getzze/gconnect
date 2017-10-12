# Plugin type

name = 'Clipboard'
file = name.to_lower()
conf = configuration_data()
conf.set('file', file)
conf.set('name', name)
conf.set('desc', 'Share the clipboard between devices')
conf.set('outcap', 'kdeconnect.clipboard')
conf.set('incap', 'kdeconnect.clipboard')
configure_file(input: plugins_template,
               output: file + '.plugin',
               install_dir: join_paths(plugin_subdir, file),
               configuration: conf)

plugin_source = file + '.vala'
plugin_deps = [
  plugins_deps,
  dependency('gtk+-3.0'),
  dependency('gdk-3.0'),
]

plugin_mod = shared_module(
  file,
  plugin_source,
  dependencies : plugin_deps,
  install: true,
  install_dir: [join_paths(plugin_subdir, file), false, false],
)
