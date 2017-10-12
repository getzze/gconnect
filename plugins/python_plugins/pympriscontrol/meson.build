# Plugin type

name = 'MprisControl'
file = name.to_lower()
conf = configuration_data()
conf.set('file', file)
conf.set('name', name)
conf.set('desc', 'Remote control your music and videos')
conf.set('outcap', 'kdeconnect.mpris')
conf.set('incap', 'kdeconnect.mpris.request')
conf.set('loader', 'Loader=python3')
configure_file(input: plugins_template,
               output: file + '.plugin',
               install_dir: join_paths(plugin_subdir, file),
               configuration: conf)

plugin_source = file + '.py'
install_data(plugin_source, install_dir: join_paths(plugin_subdir, file))
