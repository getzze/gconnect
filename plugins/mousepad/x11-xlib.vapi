
namespace PluginsGconnect.Mousepad {

    [CCode (cheader_filename = "X11/Xlib.h", cname = "XChangeKeyboardMapping")]
    int change_keyboard_mapping(X.Display display, int min_keycode, int keysyms_per_keycode, [CCode (array_length = false)] ulong[] keysyms, int num_codes);
    [CCode (cheader_filename = "X11/Xlib.h", cname = "XSync")]
    int sync(X.Display display, bool discard);
    
}

