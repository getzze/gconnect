#
#
# Plugin targets

plugins_deps = [
  dependency('json-glib-1.0'),
  dependency('libpeas-1.0'),
  gconnect_dep,
]
plugins_template = files('plugin.in')

plugins_list = [
  'clipboard',
  'battery',
  'ping',
  'telephony',
  'mousepad',
  'findmyphone',
  'runcommand',
  'mpriscontrol',
]
foreach plugin : plugins_list
  subdir(plugin)
endforeach

install_data(['helper.py', '__init__.py'], install_dir: plugin_subdir)

