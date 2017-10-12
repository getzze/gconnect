# Plugin type

name = 'MprisControl'
file = name.to_lower()
conf = configuration_data()
conf.set('file', file)
conf.set('name', name)
conf.set('desc', 'Remote control your music and videos')
conf.set('outcap', 'kdeconnect.mpris')
conf.set('incap', 'kdeconnect.mpris.request')
configure_file(input: plugins_template,
               output: file + '.plugin',
               install_dir: join_paths(plugin_subdir, file),
               configuration: conf)

plugin_source = [file + '.vala',
                 'mpriscontrol-iface.vala']
plugin_deps = [
  plugins_deps,
  dependency('gee-0.8'),
]

plugin_mod = shared_module(
  file,
  plugin_source,
  dependencies : plugin_deps,
  install: true,
  install_dir: [join_paths(plugin_subdir, file), false, false],
)
