# Plugin type

name = 'Mousepad'
file = name.to_lower()
conf = configuration_data()
conf.set('file', file)
conf.set('name', name)
conf.set('desc', 'Use your phone as a touchpad and keyboard')
conf.set('outcap', '')
conf.set('incap', 'kdeconnect.mousepad.request')
configure_file(input: plugins_template,
               output: file + '.plugin',
               install_dir: join_paths(plugin_subdir, file),
               configuration: conf)

plugin_source = file + '.vala'
plugin_deps = [
  plugins_deps,
  dependency('caribou-1.0'),
  dependency('gdk-x11-3.0'),
  dependency('gtk+-3.0'),
  dependency('gdk-3.0'),
  dependency('xtst'),
]

plugin_mod = shared_module(
  file,
  plugin_source,
  dependencies : plugin_deps,
  install: true,
  install_dir: [join_paths(plugin_subdir, file), false, false],
)
