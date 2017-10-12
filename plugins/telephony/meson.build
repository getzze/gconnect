# Plugin type

name = 'Telephony'
file = name.to_lower()
conf = configuration_data()
conf.set('file', file)
conf.set('name', name)
conf.set('desc', 'Show notifications for calls and SMS')
conf.set('outcap', 'kdeconnect.telephony.request,kdeconnect.sms.request')
conf.set('incap', 'kdeconnect.telephony')
configure_file(input: plugins_template,
               output: file + '.plugin',
               install_dir: join_paths(plugin_subdir, file),
               configuration: conf)

plugin_source = file + '.vala'
plugin_deps = [
  plugins_deps,
  dependency('gee-0.8'),
  dependency('libnotify'),
]

plugin_mod = shared_module(
  file,
  plugin_source,
  dependencies : plugin_deps,
  install: true,
  install_dir: [join_paths(plugin_subdir, file), false, false],
)
