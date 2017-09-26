/**
 * Copyright 2017 Bertrand Lacoste <getzze@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License or (at your option) version 3 or any later version
 * accepted by the membership of KDE e.V. (or its successor approved
 * by the membership of KDE e.V.), which shall act as a proxy
 * defined in Section 14 of version 3 of the license.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

using Gee;
using Peas;
// using Connection;
// using DeviceManager;
// using Config;

namespace Gconnect.DeviceManager {
    
    /* Return a negative number if p1 has higher priority than p2
     * Sort by returning a negative integer if the first value comes before the second, 
     * 0 if they are equal, or a positive integer if the first value comes after the second.
     */
    static int higher_than(Connection.DeviceLink p1, Connection.DeviceLink p2) {
        return p1.provider.priority - p2.provider.priority;
    }
    
    static string[] unique_array(string str_array, string delimiter = ",") {
        var set_array = new Gee.HashSet<string>();
        set_array.add_all_array(str_array.split(delimiter));
        return set_array.to_array();
    }
    
    string info_to_string(Peas.PluginInfo info) {
        string ret = "plugin %s: outgoing=[%s], incoming=[%s]".printf(
                        info.get_name(),
                        string.joinv(",", unique_array(info.get_external_data("X-Outgoing-Capabilities"))),
                        string.joinv(",", unique_array(info.get_external_data("X-Incoming-Capabilities"))));
        return ret;
    }
    
    public struct DeviceInfo {
        public string name;
        public string category;
        public int protocol_version;
        public string[] incoming;
        public string[] outgoing;
//        internal Gee.HashMap<string, Connection.DeviceLinkInfo> providers;
        public string ip_address;
        public string encryption;
        
        public string to_string() {
            string res = "%s (%s)\n".printf(name, category);
            res += "Protocol: %d\n".printf(protocol_version);
            res += "Incoming capabilities: %s\n".printf(string.joinv(",", incoming));
            res += "Outgoing capabilities: %s\n".printf(string.joinv(",", outgoing));
            res += "Ip address: %s\n".printf(ip_address);
            res += "Encryption info: %s\n".printf(encryption);
            return res;
        }
    }
    
    [DBus(name = "org.gconnect.device")]
    public class Device: GLib.Object {
        /* Private fields */
        private Gee.ArrayList<weak Connection.DeviceLink> device_links;
        private Gee.HashMap<string, Plugin.PluginProxy> plugins;
        private Gee.HashMap<string, Plugin.PluginProxy> plugins_by_incoming_capability;
        private Gee.HashSet<string> supported_plugins;
        private Gee.HashSet<Connection.PairingHandler> pair_requests;
        private DeviceInfo info;
        private Peas.ExtensionSet extension_set;
        private uint bus_id = 0;
        private weak DBusConnection? conn = null;
        private bool allow_dbus = true;
        
        /* Properties */
        public string id { get; private set; }
        public string name { 
            get { return this.info.name;  }
            set { 
                if (this.info.name != value) {
                    this.info.name = value;
                    name_changed(this.info.name);
                }
            }
        }
        public string category { 
            get { return this.info.category;  }
            set { this.info.category = value; }
        }
        public int protocol_version { 
            get { return this.info.protocol_version;  }
            set { this.info.protocol_version = value; }
        }
        public string[] incoming_capabilities { 
            get { return this.info.incoming;  }
            set { this.info.incoming = value; }
        }
        public string[] outgoing_capabilities { 
            get { return this.info.outgoing;  }
            set { this.info.outgoing = value; }
        }

        public string encryption_info {
            get { return this.info.encryption;  }
            set { this.info.encryption = value; }
        }

        public string ip_address {
            get { return this.info.ip_address;  }
            set { this.info.ip_address = value; }
        }

        /* Signals */
        public signal void reachable_changed(bool reachable);
        public signal void paired_changed(bool paired);
        public signal void has_pairing_requests_changed(bool has_requests);

        public signal void dbus_published();
        public signal void plugins_changed();
        public signal void pairing_error(string error);
        public signal void name_changed(string name);

        /* Constructor */
        protected Device () {
            device_links = new Gee.ArrayList<weak Connection.DeviceLink>();
            plugins = new Gee.HashMap<string, Plugin.PluginProxy>();
            plugins_by_incoming_capability = new Gee.HashMap<string, Plugin.PluginProxy>();
            supported_plugins = new Gee.HashSet<string>();
            pair_requests = new Gee.HashSet<Connection.PairingHandler>();

            //Assume every plugin is supported until addLink is called and we can get the actual list
            this.supported_plugins.add_all_array(Plugin.PluginManager.instance().outgoing_capabilities);

            this.pairing_error.connect((c, m)=> {warning("Device pairing error: %s", m);});
        }
        
        /**
        * Restores the @p device from the saved configuration
        *
        * We already know it but we need to wait for an incoming DeviceLink to communicate
        */
        public Device.from_id(string device_id) {
            this();
            this.id = device_id;
            try {
                this.info = Config.Config.instance().get_paired_device(this.id);
            } catch (IOError e) {
                pairing_error("Cannot retrieve information on paired device from cache: %s".printf(e.message));
                // TODO: tell devicelink of the problem
                error(e.message);
            }
        }

        /**
        * Device known via an incoming connection sent to us via a devicelink.
        *
        * We know everything but we don't trust it yet
        */
        public Device.from_link(NetworkProtocol.Packet identity, Connection.DeviceLink dl) {
            this();
            debug("New device object");

            this.info = DeviceInfo();
            this.id = identity.parse_device_info(ref this.info);

            add_link(dl);
        }
        

        /* Public Methods */
        public string dbus_path() { return "/modules/gconnect/devices/"+this.id; }
        
        [DBus (visible = false)]
        public unowned DBusConnection dbus_connection() { return this.conn; }
        
        //Update device information
        [DBus (visible = false)]
        public void update_info(NetworkProtocol.Packet identity) {
            var old_name = this.name;
            identity.parse_device_info(ref this.info);
            if (old_name != this.name) {
                name_changed(this.name);
            }
        }

        //Add and remove links
        [DBus (visible = false)]
        public void add_link(Connection.DeviceLink dl)
//                requires (!device_links.contains(dl))
        {
            if (device_links.contains(dl)) {
                reload_plugins();
                return;
            }
            
            var provider = dl.provider.name;
            debug("Adding link to %s via %s.", this.id, provider);

            dl.destroyed.connect(link_destroyed);
//            info.providers.@set(provider, dl.get_info());
            dl.parse_device_info(ref this.info);
            
            device_links.add(dl);

            dl.received_packet.connect(private_received_packet);

            // Sort by priority (higher first)
            device_links.sort(higher_than);

//            bool capabilities_supported = this.info.outgoing.length>0 || this.info.incoming.length>0;
//            if (capabilities_supported) {
//                supported_plugins = Plugin.PluginManager.instance().pluginsForCapabilities(info.incoming, info.outgoing);
//            } else {
//                supported_plugins = Plugin.PluginManager.instance().getPluginList().toSet();
//            }

            if (device_links.size == 1) {
                reachable_changed(true);
            }

            dl.pair_status_changed.connect(this.pair_status_changed);
            dl.pairing_request.connect(this.add_pairing_request);
            dl.pairing_request_expired.connect(this.remove_pairing_request);
            dl.pairing_error.connect((s, m)=> {this.pairing_error(m);});
            
            reload_plugins();
        }

        [DBus (visible = false)]
        public void remove_link(Connection.DeviceLink dl) {
            device_links.remove(dl);

            debug("Remove link, %d links remaining.", device_links.size);

            if (device_links.is_empty) {
//                reload_plugins();
                reachable_changed(false);
            }
        }

        public string[] available_links() {
            string[] sl = {};
            foreach (var dl in device_links) {
                sl += dl.provider.name;
            }
            return sl;
        }
        
        public bool is_paired() {
            return Config.Config.instance().is_paired(this.id);
        }
        
        public bool is_reachable() {
            return !device_links.is_empty;
        }

//         public string[] loaded_plugins() {}
//         public bool has_plugin(string name) {}
//         public string plugins_config_file() {}
//         public Plugin.Plugin plugin(string name) {}
//         void setPluginEnabled(const QString& pluginName, bool enabled);
//         bool isPluginEnabled(const QString& pluginName) const;
//         public string[] supported_plugins() { return supported_plugins.to_array(); }

        public void clean_unneeded_links() {
            if (is_paired()) {
                return;
            }
            var copy = new Gee.ArrayList<Connection.DeviceLink>();
            copy.add_all(device_links);
            foreach (var dl in copy) {
                if (!dl.link_should_be_kept_alive()) {
                    device_links.remove(dl);
                }
            }
        }

        [Callback]
        [DBus (visible = false)]
        public virtual bool send_packet(NetworkProtocol.Packet pkt)
                requires (pkt.packet_type != NetworkProtocol.PACKET_TYPE_PAIR)
                requires (pkt.packet_type != NetworkProtocol.PACKET_TYPE_IDENTITY)
                requires (is_paired())
        {
            if (pkt.packet_type in info.incoming) {
                foreach (var dl in device_links) {
                    if (dl.send_packet(pkt)) { return true;}
                }
            } else {
                message("Device %s does not accept incoming packet of type %s", info.name, pkt.packet_type);
            }
            return false;
        }

        [Callback]
        public void request_pair() { // to all links
            if (is_paired()) {
                this.pairing_error(_("Already paired"));
                return;
            }

            if (!is_reachable()) {
                this.pairing_error(_("Device not reachable"));
                return;
            }

            foreach (var dl in device_links) {
                dl.user_requests_pair();
            }
        }
        
        [Callback]
        public void unpair() { // from all links
            debug("Device links attached to %s: %d", this.id, device_links.size);
            if (device_links.is_empty) {
                warning("No device link to communicate with device.");
                return;
            }
            foreach (var dl in device_links) {
                dl.user_requests_unpair();
            }
            try {
                Config.Config.instance().remove_paired_device(this.id);
            } catch (IOError e) {
                warning("Could not unpair: %s", e.message);
                return;
            }
            paired_changed(false);
        }
        
        public void reload_plugins() {
            deactivate_plugins();
            activate_plugins();
        }
        
        private void activate_plugins() {
            init_plugins();
        }
        
        private void deactivate_plugins() {
            if (extension_set != null) {
                extension_set.@foreach((ext_set, info, extension) => {
                    (extension as Plugin.Plugin).deactivate();
                    plugins.unset(info.get_name());
                });
                extension_set = null;
            }
            plugins.clear();
        }
        
        public void init_plugins() {
            debug("Preload plugin engine");
            var engine = Plugin.PluginManager.instance().engine;
            debug("Activate all available plugins for device %s.", this.id);
            this.extension_set = new Peas.ExtensionSet(engine, typeof(Plugin.Plugin), "device", this);
            
            this.extension_set.@foreach((ext_set, info, extension) => {
                var pname = info.get_name();
                if (!plugins.has_key(pname)) {
                    var pp = new Plugin.PluginProxy(info, this);
                    plugins[pname] = (owned)pp;
                }
                (extension as Plugin.Plugin).activate(pname);
                debug("Activate " + info_to_string(info));
            });

            this.extension_set.extension_added.connect((info, extension) => {
                if (is_plugin_allowed(info)) {
                    var pname = info.get_name();
                    if (!plugins.has_key(pname)) {
                        var pp = new Plugin.PluginProxy(info, this);
                        plugins[pname] = (owned)pp;
                    }
                    (extension as Plugin.Plugin).activate(pname);
                    debug("Activate " + info_to_string(info));
                }
            });
            this.extension_set.extension_removed.connect((info, extension) => {
                (extension as Plugin.Plugin).deactivate();
                plugins.unset(info.get_name());
            });
        }

        private bool is_plugin_allowed(Peas.PluginInfo info) {
            if (info.is_loaded()) {
                var outc = unique_array(info.get_external_data("X-Outgoing-Capabilities"));
                if ("debug" in outc) {
                    return true;
                }
                foreach (var cap in outc) {
                    if (cap in incoming_capabilities) {
                        return true;
                    }
                }
            }
            return false;
        }

        [DBus (visible = false)]
        public Plugin.PluginProxy? get_plugin(string name) {
            return plugins[name];
        }

        [Callback]
        public void accept_pairing() {
            debug("Pairing was accepted by user");
            bool res = false;
            foreach (var dl in device_links) {
                res = res || dl.user_accepts_pair();
            }
            if (!res) {
                warning("No pair requests to accept!");
            }
        }

        [Callback]
        public void reject_pairing() {
            debug("Pairing was rejected by user");
            bool res = false;
            foreach (var dl in device_links) {
                res = res || dl.user_rejects_pair();
            }
            if (!res) {
                warning("No pair requests to reject!");
            }
        }
        
        [Callback]
        public bool has_pairing_requests() {
            foreach (var dl in device_links) {
                if (dl.has_pairing_handler()) {
                    return true;
                }
            }
            return false;
        }

        public string icon_name() {
            return icon_for_status(true, false);
        }
        
        public string status_icon_name() {
            return icon_for_status(is_reachable(), is_paired());
        }
        
        [DBus (visible = false)]
        public void publish (DBusConnection conn) {
            this.conn = conn;
            try	{
                string path = this.dbus_path();
                this.bus_id = conn.register_object(path, this);
                debug("Register device %s to dbus: %s", this.id, path);
                dbus_published();
			} catch (IOError e) {
				warning ("Could not register objects: %s", e.message);
			}
        }

        [DBus (visible = false)]
        public void unpublish () throws IOError {
            if (this.conn == null) {
                return;
            }
            // Unpublish plugins
            deactivate_plugins();
            
            // Unpublish device
            try	{
                if (!this.conn.unregister_object(this.bus_id)) {
					warning("Failed to unregister object id %u", this.bus_id);
                } else {
                    debug("Unregister device %s from dbus.", this.name);
                    this.bus_id = 0;
                }
			} catch (IOError e) {
				warning ("Could not register objects: %s", e.message);
			}
            this.conn = null;
        }

        private bool is_packet_allowed(string type, Peas.PluginInfo info) {
            var inc = unique_array(info.get_external_data("X-Incoming-Capabilities"));
            if ("debug" in inc) {
                return true;
            }
            if (type in inc) {
                return true;
            }
            return false;
        }
        
        [Callback]
        private void private_received_packet(NetworkProtocol.Packet pkt)
            requires (pkt.packet_type != NetworkProtocol.PACKET_TYPE_PAIR)
        {
            if (is_paired()) {
                int treated = 0;
                // TODO: use a dictionary with incoming-capabilities instead
                foreach (var pp in plugins.values) {
                    if (pp.receive(pkt)) {
                        treated += 1;
                    }
                }
                if (treated == 0) {
                    warning("Discarding unsupported packet %s for device %s.", pkt.packet_type, this.name);
                }
            } else {
                debug("Device %s not paired, ignoring packet %s", this.name, pkt.packet_type);
                unpair();
            }

        }
        
        [Callback]
        private void link_destroyed(Connection.DeviceLink sender, string device_id) {
            if (device_id == this.id) {
                remove_link(sender);
            } else {
                warning("Asking device %s to destroy link to %s, mismatch.", this.id, device_id);
            }
        }
        
        [Callback]
        private void pair_status_changed(Connection.DeviceLink device_link, Connection.DeviceLink.PairStatus status) {
            if (status == Connection.DeviceLink.PairStatus.NOT_PAIRED) {
                try {
                    Config.Config.instance().remove_paired_device(this.id);
                } catch (IOError e) {
                    pairing_error("Cannot remove paired device from cache: %s".printf(e.message));
                    // TODO: tell devicelink of the problem
                    paired_changed(true);
                }

                foreach (var dl in device_links) {
                    if (dl != device_link) {
                        dl.set_pair_status(Connection.DeviceLink.PairStatus.NOT_PAIRED);
                    }
                }
                deactivate_plugins();
            } else {
                try {
                    Config.Config.instance().add_paired_device(this.id, this.info);
                } catch (IOError e) {
                    pairing_error("Cannot add paired device to cache: %s".printf(e.message));
                    // TODO: tell devicelink of the problem
                    error(e.message);
                }
                activate_plugins();
            }


            bool is_trusted = (status == Connection.DeviceLink.PairStatus.PAIRED);
            GLib.info("Device %s paired: %s", this.id, is_trusted.to_string());
            paired_changed(is_trusted);
            assert(is_trusted == this.is_paired());
        }

        [Callback]
        private void add_pairing_request(Connection.PairingHandler handler) {
            bool was_empty = pair_requests.is_empty;
            pair_requests.add(handler);

            if (was_empty != pair_requests.is_empty) {
                has_pairing_requests_changed(!pair_requests.is_empty);
            }
        }

        [Callback]
        private void remove_pairing_request(Connection.PairingHandler handler) {
            bool was_empty = pair_requests.is_empty;
            pair_requests.remove(handler);

            if (was_empty != pair_requests.is_empty) {
                has_pairing_requests_changed(!pair_requests.is_empty);
            }
        }
        
        private string icon_for_status(bool reachable, bool paired) {
            string cat = this.category;
            if (cat == "desktop") {
                cat = "laptop"; // We don't have desktop icon yet
            } else if (cat != "laptop") {
                cat = "smartphone";
            }

            string status = (reachable? (paired? "connected" : "disconnected") : "trusted");
            return cat+status;
        }
    }
}
