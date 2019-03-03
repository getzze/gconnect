#
#
# Daemon target
daemon_name = meson.project_name() + 'd'

daemon_deps = [
  dependency('gee-0.8'),
  dependency('libnotify'),
  gconnect_dep,
]

gconnect_daemon = executable(daemon_name, 'daemon.vala',
                              dependencies : daemon_deps,
                              link_with : gconnect_lib,
                              install: true)
