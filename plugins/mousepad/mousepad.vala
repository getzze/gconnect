using GLib;
using Peas;
using Gconnect;
using Gtk;
using Gdk;
//using XTest;

// Use a different namespace for each plugin to avoid using the same class names
namespace PluginsGconnect.Mousepad {
    
    public abstract class SimpleProxy : GLib.Object {
        protected unowned Gconnect.Plugin.PluginProxy proxy;
        protected string name;

        protected unowned DBusConnection dbus_connection;
        
        public SimpleProxy(Gconnect.Plugin.PluginProxy proxy) {
            this.proxy = proxy;
            this.name = proxy.name;
            this.proxy.received_packet.connect(receive);

            if (this.proxy.dbus_connection() != null) {
                publish();
            } else {
                // Delayed publication on DBus
                this.proxy.published.connect(publish);
            }
        }

        protected abstract void receive(Gconnect.NetworkProtocol.Packet pkt);
        protected abstract void publish();
        [DBus (visible = false)]
        public abstract void unpublish();
    }


    enum MouseButtons {
        LeftMouseButton = 1,
        MiddleMouseButton = 2,
        RightMouseButton = 3,
        MouseWheelUp = 4,
        MouseWheelDown = 5
    }

    public class MousepadProxy : SimpleProxy {
        private const string PACKET_TYPE_REQUEST = "kdeconnect.mousepad.request";
        private const string PACKET_TYPE_ECHO = "kdeconnect.mousepad.echo";
        private const string PACKET_TYPE_KEYBOARDSTATE = "kdeconnect.mousepad.keyboardstate";
        
        private bool X11 = true;
        private Caribou.XAdapter xkbd;
        private unowned X.Display display = null;
        private unowned string[] argv = null;

        private int[] SpecialKeysMap = {
            0,                   // Invalid
            Gdk.Key.BackSpace,   // 1
            Gdk.Key.Tab,         // 2
            Gdk.Key.Linefeed,    // 3
            Gdk.Key.Left,        // 4
            Gdk.Key.Up,          // 5
            Gdk.Key.Right,       // 6
            Gdk.Key.Down,        // 7
            Gdk.Key.Page_Up,     // 8
            Gdk.Key.Page_Down,   // 9
            Gdk.Key.Home,        // 10
            Gdk.Key.End,         // 11
            Gdk.Key.Return,      // 12
            Gdk.Key.Delete,      // 13
            Gdk.Key.Escape,      // 14
            Gdk.Key.Sys_Req,     // 15
            Gdk.Key.Scroll_Lock, // 16
            0,                   // 17
            0,                   // 18
            0,                   // 19
            0,                   // 20
            Gdk.Key.F1,          // 21
            Gdk.Key.F2,          // 22
            Gdk.Key.F3,          // 23
            Gdk.Key.F4,          // 24
            Gdk.Key.F5,          // 25
            Gdk.Key.F6,          // 26
            Gdk.Key.F7,          // 27
            Gdk.Key.F8,          // 28
            Gdk.Key.F9,          // 29
            Gdk.Key.F10,         // 30
            Gdk.Key.F11,         // 31
            Gdk.Key.F12,         // 32
        };

        construct {
            if (Gtk.init_check(ref this.argv)) {
                display = Gdk.X11.get_default_xdisplay();
                // Cannot instanciate Caribou.XAdapter directly, otherwise Caribou segfaults...
                Caribou.DisplayAdapter xadapter = Caribou.DisplayAdapter.get_default();
                xkbd = xadapter as Caribou.XAdapter;
            }
        }
        
        public MousepadProxy(Gconnect.Plugin.PluginProxy proxy) {
            base(proxy);
            if (display == null || xkbd == null) {
                warning("No X11 display available");
                X11 = false;
            }
        }

        void send_keyval (uint keysym, uint mask) {
            this.xkbd.mod_latch(mask);
            this.xkbd.keyval_press(keysym);
            this.xkbd.keyval_release(keysym);
            this.xkbd.mod_unlatch(mask);
        }

        private void handle_packet_X11(Gconnect.NetworkProtocol.Packet pkt) {
            double dx = pkt.has_field("dx") ? pkt.get_double("dx") : 0;
            double dy = pkt.has_field("dy") ? pkt.get_double("dy") : 0;

            bool isSingleClick = pkt.has_field("singleclick") ? pkt.get_bool("singleclick") : false;
            bool isDoubleClick = pkt.has_field("doubleclick") ? pkt.get_bool("doubleclick") : false;
            bool isMiddleClick = pkt.has_field("middleclick") ? pkt.get_bool("middleclick"): false;
            bool isRightClick = pkt.has_field("rightclick") ? pkt.get_bool("rightclick") : false;
            bool isSingleHold = pkt.has_field("singlehold") ? pkt.get_bool("singlehold") : false;
            bool isSingleRelease = pkt.has_field("singlerelease") ? pkt.get_bool("singlerelease") : false;
            bool isScroll = pkt.has_field("scroll") ? pkt.get_bool("scroll") : false;
            string key = pkt.has_field("key") ? pkt.get_string("key") : "";
            int specialKey = pkt.has_field("specialKey") ? pkt.get_int("specialKey") : 0;
            
//            bool left_handed = is_left_handed(this.display);
//            int mainMouseButton = left_handed ? MouseButtons.RightMouseButton : MouseButtons.LeftMouseButton;
//            int secondaryMouseButton = left_handed ? MouseButtons.LeftMouseButton : MouseButtons.RightMouseButton;

            if (isSingleClick) {
                XTest.fake_button_event(this.display, Gdk.BUTTON_PRIMARY, true, 0);
                XTest.fake_button_event(this.display, Gdk.BUTTON_PRIMARY, false, 0); 
            } else if (isDoubleClick) {
                XTest.fake_button_event(this.display, Gdk.BUTTON_PRIMARY, true, 0);
                XTest.fake_button_event(this.display, Gdk.BUTTON_PRIMARY, false, 0); 
                XTest.fake_button_event(this.display, Gdk.BUTTON_PRIMARY, true, 0);
                XTest.fake_button_event(this.display, Gdk.BUTTON_PRIMARY, false, 0); 
            } else if (isMiddleClick) {
                XTest.fake_button_event(this.display, Gdk.BUTTON_MIDDLE, true, 0);
                XTest.fake_button_event(this.display, Gdk.BUTTON_MIDDLE, false, 0); 
            } else if (isRightClick) {
                XTest.fake_button_event(this.display, Gdk.BUTTON_SECONDARY, true, 0);
                XTest.fake_button_event(this.display, Gdk.BUTTON_SECONDARY, false, 0); 
            } else if (isSingleHold){
                //For drag'n drop
                XTest.fake_button_event(this.display, Gdk.BUTTON_PRIMARY, true, 0);
            } else if (isSingleRelease){
                //For drag'n drop. NEVER USED (release is done by tapping, which actually triggers a isSingleClick). Kept here for future-proofnes.
                XTest.fake_button_event(this.display, Gdk.BUTTON_PRIMARY, false, 0);
            } else if (isScroll) {
                if (dy < 0) {
                    XTest.fake_button_event(this.display, MouseButtons.MouseWheelDown, true, 0);
                    XTest.fake_button_event(this.display, MouseButtons.MouseWheelDown, false, 0); 
                } else if (dy > 0) {
                    XTest.fake_button_event(this.display, MouseButtons.MouseWheelUp, true, 0);
                    XTest.fake_button_event(this.display, MouseButtons.MouseWheelUp, false, 0); 
                }
            } else if (key != "" || specialKey != 0) {
                bool ctrl  = pkt.has_field("ctrl")  ? pkt.get_bool("ctrl")  : false;
                bool alt   = pkt.has_field("alt")   ? pkt.get_bool("alt")   : false;
                bool shift = pkt.has_field("shift") ? pkt.get_bool("shift") : false;

                uint mask = 0;
                if (ctrl)  mask |= Gdk.ModifierType.CONTROL_MASK;
                if (shift) mask |= Gdk.ModifierType.SHIFT_MASK;
                if (alt)   mask |= Gdk.ModifierType.MOD1_MASK;  // Alt key

//                if (ctrl)  XTest.fake_key_event(this.display, this.display.keysym_to_keycode(Gdk.Key.Control_L), true, 0);
//                if (alt)   XTest.fake_key_event(this.display, this.display.keysym_to_keycode(Gdk.Key.Alt_L),     true, 0);
//                if (shift) XTest.fake_key_event(this.display, this.display.keysym_to_keycode(Gdk.Key.Shift_L),   true, 0);
                

                if (specialKey != 0 && specialKey < SpecialKeysMap.length) {
                    uint keysym = SpecialKeysMap[specialKey];
                    send_keyval(keysym, mask);
//                    int keycode = this.display.keysym_to_keycode (SpecialKeysMap[specialKey]);
//                    XTest.fake_key_event(this.display, keycode, true, 0);
//                    XTest.fake_key_event(this.display, keycode, false, 0);                
                } else {
                    unichar c;
                    for (int i = 0; key.get_next_char (ref i, out c);) {
                        uint keysym = Gdk.unicode_to_keyval(c);
                        send_keyval(keysym, mask);
                    }
                }

//                if (shift) XTest.fake_key_event(this.display, display.keysym_to_keycode (Gdk.Key.Shift_L),   false, 0);
//                if (alt)   XTest.fake_key_event(this.display, display.keysym_to_keycode (Gdk.Key.Alt_L),     false, 0);
//                if (ctrl)  XTest.fake_key_event(this.display, display.keysym_to_keycode (Gdk.Key.Control_L), false, 0);
                
            } else {
                // Move mouse
                XTest.fake_relative_motion_event(this.display, (int) dx, (int) dy, 0);
            }
        }

        protected override void receive(Gconnect.NetworkProtocol.Packet pkt) {
            if (X11) {
                handle_packet_X11(pkt);
            }
        }

        protected override void publish() {}

        [DBus (visible = false)]
        public override void unpublish() {}
    }


    public class Mousepad : GLib.Object, Gconnect.Plugin.Plugin {
        public unowned Gconnect.DeviceManager.Device device { get; construct set; }
        private MousepadProxy worker = null;

        /* The "constructor" with the plugin name as argument */
        public void activate(string name) {
            this.worker = new MousepadProxy(this.device.get_plugin(name));
        }
        
        public void deactivate() {
            if (this.worker != null) {
                this.worker.unpublish();
                this.worker = null;
            }
        }
    }
}

// Register extension types
[ModuleInit]
public void peas_register_types (TypeModule module) {
        var objmodule = module as Peas.ObjectModule;

        objmodule.register_extension_type(typeof (Gconnect.Plugin.Plugin), typeof (PluginsGconnect.Mousepad.Mousepad));
}
