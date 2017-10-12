using GLib;
using Peas;
using Gconnect;
using Gtk;
using Gdk;

// Use a different namespace for each plugin to avoid using the same class names
namespace PluginsGconnect.RemoteKeyboard {
    
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

    [DBus(name = "org.gconnect.plugins.remotekeyboard")]
    public class RemoteKeyboardProxy : SimpleProxy {
        private const string PACKET_TYPE_REQUEST = "kdeconnect.mousepad.request";
        private const string PACKET_TYPE_ECHO = "kdeconnect.mousepad.echo";
        private const string PACKET_TYPE_KEYBOARDSTATE = "kdeconnect.mousepad.keyboardstate";
        
        private bool remote_state = false;
        
        public signal void key_press_received (string key,
                int special_key = 0, bool shift = false, bool ctrl = false, bool alt = false);
        public signal void remote_state_changed (bool state);
        
        public RemoteKeyboardProxy(Gconnect.Plugin.PluginProxy proxy) {
            base(proxy);
        }

        public void send_key_press(string key, int special_key,
                                bool shift, bool ctrl, bool alt, bool sendAck) {
            var pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_REQUEST);
            pkt.set_string("key", key);
            pkt.set_int("specialKey", special_key);
            pkt.set_bool("shift", shift);
            pkt.set_bool("ctrl", ctrl);
            pkt.set_bool("alt", alt);
            pkt.set_bool("sendAck", sendAck);
            this.proxy.request(pkt);
        }

//        public void sendQKeyEvent(Variant key_event, bool sendAck) const
//        {
//            if (!keyEvent.contains("key"))
//                return;
//            int k = translateQtKey(keyEvent.value("key").toInt());
//            int modifiers = keyEvent.value("modifiers").toInt();
//            sendKeyPress(keyEvent.value("text").toString(), k,
//                         modifiers & Qt::ShiftModifier,
//                         modifiers & Qt::ControlModifier,
//                         modifiers & Qt::AltModifier,
//                         sendAck);
//        }

//        public int translateQtKey(int qtKey) const
//        {
//            return specialKeysMap.value(qtKey, 0);
//        }

        protected override void receive(Gconnect.NetworkProtocol.Packet pkt) {
            if (pkt.packet_type == PACKET_TYPE_ECHO) {
                if (!pkt.has_field("isAck") || !pkt.has_field("key")) {
                    warning("Invalid packet of type %s", PACKET_TYPE_ECHO);
                    return;
                }
//                debug("Received keypress");
                key_press_received(pkt.get_string("key"),
                        pkt.has_field("specialKey") ? pkt.get_int("specialKey") : 0,
                        pkt.has_field("shift") ? pkt.get_bool("shift") : false,
                        pkt.has_field("ctrl") ? pkt.get_bool("ctrl") : false,
                        pkt.has_field("alt") ? pkt.get_bool("alt") : false
                );
            } else if (pkt.packet_type == PACKET_TYPE_KEYBOARDSTATE) {
//                debug("Received keyboardstate");
                if (remote_state != pkt.get_bool("state")) {
                    remote_state = pkt.get_bool("state");
                    remote_state_changed(remote_state);
                }
            }
        }

        protected override void publish() {
            this.proxy.register(publish_dbus);
        }

        [DBus (visible = false)]
        public override void unpublish() {
            this.proxy.unpublish();
        }
        
        private uint publish_dbus(DBusConnection conn) throws IOError {
            this.dbus_connection = conn;

            string path = this.proxy.dbus_path();
            uint bus_id = conn.register_object(path, this);
            this.proxy.log("Publish interface to dbus path %s".printf(path));

            return bus_id;
        }
    }


    public class RemoteKeyboard : GLib.Object, Gconnect.Plugin.Plugin {
        public unowned Gconnect.DeviceManager.Device device { get; construct set; }
        private RemoteKeyboardProxy worker = null;

        /* The "constructor" with the plugin name as argument */
        public void activate(string name) {
            this.worker = new RemoteKeyboardProxy(this.device.get_plugin(name));
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

        objmodule.register_extension_type(typeof (Gconnect.Plugin.Plugin), typeof (PluginsGconnect.RemoteKeyboard.RemoteKeyboard));
}
