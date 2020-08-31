using GLib;
using Peas;
using Gconnect;


namespace PluginsGconnect.Battery {
    
    public abstract class SimpleProxy : GLib.Object {
        protected unowned Gconnect.Plugin.PluginProxy proxy;
        protected string name;

        protected unowned DBusConnection dbus_connection;
        
        protected SimpleProxy(Gconnect.Plugin.PluginProxy proxy) {
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

    [DBus(name = "org.gconnect.plugins.battery")]
    public class BatteryProxy : SimpleProxy {
        protected const string PACKET_TYPE_REQUEST = "kdeconnect.battery.request";
        
//        private int _charge = -1;
//        private bool _is_charging;
//        public signal void state_changed(bool is_charging);
//        public signal void charge_changed(int charge);

        public int charge { get; private set; default = -1; }
        public bool is_charging { get; private set; }
        
        public BatteryProxy(Gconnect.Plugin.PluginProxy proxy) {
            base(proxy);
            Notify.init("gconnect");
            request();
        }

        public void request() {
            var pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_REQUEST);
            pkt.set_bool("request", true);
            this.proxy.request(pkt);
        }

        protected override void receive(Gconnect.NetworkProtocol.Packet pkt) {
            bool current_is_charging = pkt.has_field("isCharging") ? pkt.get_bool("isCharging") : false;
            int current_charge = pkt.has_field("currentCharge") ? pkt.get_int("currentCharge") : -1;
            // None = 0, Low = 1
            int threshold_event = pkt.has_field("thresholdEvent") ? pkt.get_int("thresholdEvent") : 0;
            string text = current_is_charging ? "charging" : "discharging";
            this.proxy.log("Battery %s (%d%%)".printf(text, current_charge));

            if ((current_charge > 0 && this.charge != current_charge) || this.is_charging != current_is_charging) {
                this.is_charging = current_is_charging;
                this.charge = current_charge;

//                state_changed.emit(this.is_charging);
//                charge_changed.emit(this.charge);
            }

            if (threshold_event == 1 && !current_is_charging) {
                var title = "%s: low battery".printf(this.proxy.device_name);
                var mess = "Battery at %d%%".printf(current_charge);

                var notification = new Notify.Notification (title, mess, "battery-symbolic");
                try {
                    notification.show();
                } catch (Error e) {
                    debug("Cannot display notfication: %s", e.message);
                }
            }
        }
        
//        public bool is_charging() {
//            return _is_charging;
//        }

//        public int charge() {
//            return _charge;
//        }

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

    public class Battery : GLib.Object, Gconnect.Plugin.Plugin {
        public unowned Gconnect.DeviceManager.Device device { get; construct set; }
        private BatteryProxy worker = null;

        /* The "constructor" with the plugin name as argument */
        public void activate(string name) {
            this.worker = new BatteryProxy(this.device.get_plugin(name));
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

        objmodule.register_extension_type(typeof (Gconnect.Plugin.Plugin), typeof (PluginsGconnect.Battery.Battery));
}
