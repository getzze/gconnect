# Gconnect

Implementation of the KDEConnect protocol in Vala using GLib2.
Plugins can be written in Vala, C Python or Lua using [libpeas](https://github.com/GNOME/libpeas).

# Building

## Dependencies:

- vala
- meson
- glib2
- gobject-introspection
- libgee
- libpeas
- json-glib
- gnutls
- libnotify

For the plugins:

- gtk-3
- caribou

To build gconnect:

    mkdir build && cd $_
    meson ..
    ninja && sudo ninja install

## Experimental bluetooth support:

Set the `gconnect_bluetooth` option to `true` in the `meson_options.txt` file or with the command-line:

    meson configure -Dgconnect_bluetooth=true
    
Then build.

It needs a modified apk.
See https://www.reddit.com/r/linux/comments/6ggb36/kde_connect_works_over_bluetooth_now_please_help/

# Usage

Start the daemon with:

    gconnectd

Or with the debug option to get more information:

    gconnectd --debug

By default, `gconnect` is installed in `/usr/local`, if you get an error because of missing libraries, try:
    
    LD_LIBRARY_PATH=/usr/local/lib/ GI_TYPELIB_PATH=/usr/local/lib/girepository-1.0 gconnectd
    


# Special Thanks

This project uses a few pieces of other projects, thanks to:

- [KDEConnect](https://github.com/KDE/kdeconnect-kde) for the protocol.
- [mconnect](https://github.com/bboozzoo/mconnect) other implementation in Vala of the kdeconnect protocol.
