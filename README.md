# Gconnect

Implementation of the KDEConnect protocol in Vala using GLib2.
Plugins can be written in Vala, C Python or Lua using [libpeas](https://github.com/GNOME/libpeas).

# Building

## Dependencies:

- vala
- cmake
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
    cmake ..
    make && make install

## Project structure

This project uses the [Vala project template](https://github.com/flplv/vala-cmake-example).
Thanks to its developers for simplifying all this boring and complex work.

# Special Thanks

This project uses a few pieces of other projects, thanks to:

- [Vala project template](https://github.com/flplv/vala-cmake-example) CMake template.
- [KDEConnect](https://github.com/KDE/kdeconnect-kde) for the protocol.
- [mconnect](https://github.com/bboozzoo/mconnect) other implementation in Vala of the kdeconnect protocol.
