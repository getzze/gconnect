using GLib;
using Peas;
using Gconnect;


namespace PluginsGconnect.Ping {
    
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

    [DBus(name = "org.gconnect.plugins.ping")]
    public class PingProxy : SimpleProxy {
        protected const string PACKET_TYPE_REQUEST = "kdeconnect.ping";
        
        public PingProxy(Gconnect.Plugin.PluginProxy proxy) {
            base(proxy);
            Notify.init("gconnect");
        }

        protected override void receive(Gconnect.NetworkProtocol.Packet pkt) {
            var title = this.proxy.device_name;
            var mess = pkt.has_field("message") ? pkt.get_string("message") : "Ping!";

            var notification = new Notify.Notification (title, mess, "dialog-information");
            try {
                notification.show();
            } catch (Error e) {
                debug("Cannot display notfication: %s", e.message);
            }
        }
        
        public void send_ping() {
            var pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_REQUEST);
            this.proxy.request(pkt);
        }

        public void send_message(string mess) {
            var pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_REQUEST);
            pkt.set_string("message", mess);
            this.proxy.request(pkt);
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

    public class Ping : GLib.Object, Gconnect.Plugin.Plugin {
        public unowned Gconnect.DeviceManager.Device device { get; construct set; }
        private PingProxy worker = null;

        /* The "constructor" with the plugin name as argument */
        public void activate(string name) {
            this.worker = new PingProxy(this.device.get_plugin(name));
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

        objmodule.register_extension_type(typeof (Gconnect.Plugin.Plugin), typeof (PluginsGconnect.Ping.Ping));
}
