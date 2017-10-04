using GLib;
using Peas;
using Gconnect;
using Gtk;
using Gdk;

// Use a different namespace for each plugin to avoid using the same class names
namespace PluginsGconnect.Clipboard {
    
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

    public class ClipboardProxy : SimpleProxy {
        private const string PACKET_TYPE_CLIPBOARD = "kdeconnect.clipboard";
        
        private Gtk.Clipboard clipboard = null;
        private unowned string[] argv = null;
        
        public ClipboardProxy(Gconnect.Plugin.PluginProxy proxy) {
            base(proxy);
            if (Gtk.init_check(ref this.argv)) {
                clipboard = Gtk.Clipboard.@get(Gdk.SELECTION_CLIPBOARD);
            }
            if (clipboard == null) {
                warning("Cannot use clipboard on default display");
            } else {
                clipboard.owner_change.connect((s,e) => {
                    propagate();
                });
            }
        }

        private void propagate() {
            var text = clipboard.wait_for_text();
            var pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_CLIPBOARD);
            pkt.set_string("content", text);
            this.proxy.request(pkt);
        }

        protected override void receive(Gconnect.NetworkProtocol.Packet pkt) {
            if (clipboard == null) {
                return;
            }
            string content = pkt.get_string("content");
            clipboard.set_text(content, -1);
        }

        protected override void publish() {}

        [DBus (visible = false)]
        public override void unpublish() {}
    }


    public class Clipboard : GLib.Object, Gconnect.Plugin.Plugin {
        public unowned Gconnect.DeviceManager.Device device { get; construct set; }
        private ClipboardProxy worker = null;

        /* The "constructor" with the plugin name as argument */
        public void activate(string name) {
            this.worker = new ClipboardProxy(this.device.get_plugin(name));
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

        objmodule.register_extension_type(typeof (Gconnect.Plugin.Plugin), typeof (PluginsGconnect.Clipboard.Clipboard));
}
