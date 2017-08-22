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
    
    void warn(string info) {
        warning("Device pairing error: %s", info);
    }

    /* Return a negative number if p1 has higher priority than p2
     * Sort by returning a negative integer if the first value comes before the second, 
     * 0 if they are equal, or a positive integer if the first value comes after the second.
     */
    static int higher_than(Connection.DeviceLink p1, Connection.DeviceLink p2) {
        return p1.provider().priority - p2.provider().priority;
    }
    
    public struct DeviceInfo {
        public string name;
        public string category;
        public int protocol_version;
        public string[] incoming;
        public string[] outgoing;
    }
    
    public class Device: GLib.Object {
        /* Private fields */
        private Gee.ArrayList<Connection.DeviceLink> _device_links;
        private Gee.HashMap<string, Plugin.Plugin> _plugins;
        private Gee.HashMap<string, Plugin.Plugin> _plugins_by_incoming_capability;
        private Gee.HashSet<string> _supported_plugins;
        private Gee.HashSet<Connection.PairingHandler> _pair_requests;
        private DeviceInfo info;
        private Peas.ExtensionSet _extension_set;
        
        /* Signals */
        public signal void reachable_changed(bool reachable);
        public signal void paired_changed(bool paired);
        public signal void has_pairing_requests_changed(bool has_requests);

        public signal void plugins_changed();
        public signal void pairing_error(string error);
        public signal void name_changed(string name);

        /* Constructor */
        /**
        * Restores the @p device from the saved configuration
        *
        * We already know it but we need to wait for an incoming DeviceLink to communicate
        */
        public Device.from_id(GLib.Object parent, string device_id) {
            this.id = device_id;
            this.info = Config.Config.instance().get_paired_device(this.id);

            this.name = info.name;
            this.category = info.category;

            //Assume every plugin is supported until addLink is called and we can get the actual list
            this._supported_plugins = new Gee.HashSet<string>();
            this._supported_plugins.add_all_array(Plugin.PluginManager.instance().outgoing_capabilities);

            this.pairing_error.connect((c, m)=> {warning("Device pairing error: %s", m);});
        }

        /**
        * Device known via an incoming connection sent to us via a devicelink.
        *
        * We know everything but we don't trust it yet
        */
        public Device.from_link(GLib.Object parent, NetworkProtocol.Packet identity, Connection.DeviceLink dl) {
            this.id = identity.get_string("deviceId");
            this.name = identity.get_string("deviceName");

            add_link(identity, dl);

            this.pairing_error.connect((c, m)=> {warning("Device pairing error: %s", m);});
        }
        
        /* Properties */
        public string id { get; private set; }
        public string name { 
            get {
                return name;
            }
            set{ 
                if (this.name != value) {
                    name = value;
                    name_changed(name);
                }
            }
        }
        public string category { get; private set; }
        public int protocol_version { get; private set; default=NetworkProtocol.PROTOCOL_VERSION;}
        public string encryption_info { get; set; }

        /* Public Methods */
        public string dbus_path() { return "/modules/gconnect/devices/"+id; }
        
        //Add and remove links
        public void add_link(NetworkProtocol.Packet identity, Connection.DeviceLink dl)
                requires (!_device_links.contains(dl))
        {
            debug("Adding link to %s via %s.", this.id, dl.provider().name);

            this.protocol_version = identity.get_int("protocolVersion");
            if (this.protocol_version != NetworkProtocol.PROTOCOL_VERSION) {
                warning("%s - warning, device uses a different protocol version %d, expected %d.", this.name, this.protocol_version, NetworkProtocol.PROTOCOL_VERSION);
            }

            dl.destroyed.connect(link_destroyed);

            _device_links.add(dl);

            //re-read the device name from the identity Packet because it could have changed
            this.name = identity.get_string("deviceName");
            this.category = identity.get_string("deviceType");

            //Theoretically we will never add two links from the same provider (the provider should destroy
            //the old one before this is called), so we do not have to worry about destroying old links.
            //-- Actually, we should not destroy them or the provider will store an invalid ref!

            dl.received_packet.connect(private_received_packet);

            // Sort by priority (higher first)
            _device_links.sort(higher_than);

            bool capabilities_supported = identity.has_field("incomingCapabilities") || identity.has_field("outgoingCapabilities");
            if (capabilities_supported) {
                info.outgoing = identity.get_strv("outgoingCapabilities");
                info.incoming = identity.get_strv("incomingCapabilities");

//                 _supported_plugins = Plugin.PluginManager.instance().pluginsForCapabilities(info.incoming, info.outgoing);
            } else {
//                 _supported_plugins = Plugin.PluginManager.instance().getPluginList().toSet();
            }

            reload_plugins();

            if (_device_links.size == 1) {
                reachable_changed(true);
            }

            dl.pair_status_changed.connect(this.pair_status_changed);
            dl.pairing_request.connect(this.add_pairing_request);
            dl.pairing_request_expired.connect(this.remove_pairing_request);
            dl.pairing_error.connect((s, m)=> {this.pairing_error(m);});
        }

        public void remove_link(Connection.DeviceLink dl) {
            _device_links.remove(dl);

            debug("Remove link, %d links remaining.", _device_links.size);

            if (_device_links.is_empty) {
                reload_plugins();
                reachable_changed(false);
            }
        }

        public string[] available_links() {
            string[] sl = {};
            foreach (var dl in _device_links) {
                sl += dl.provider().name;
            }
            return sl;
        }
        
        public bool is_paired() {
            return (this.id in Config.Config.instance().get_paired_devices());
        }
        
        public bool is_reachable() {
            return !_device_links.is_empty;
        }

//         public string[] loaded_plugins() {}
//         public bool has_plugin(string name) {}
//         public string plugins_config_file() {}
//         public Plugin.Plugin plugin(string name) {}
//         void setPluginEnabled(const QString& pluginName, bool enabled);
//         bool isPluginEnabled(const QString& pluginName) const;
//         public string[] supported_plugins() { return _supported_plugins.to_array(); }

        public void clean_unneeded_links() {
            if (is_paired()) {
                return;
            }
            var copy = new Gee.ArrayList<Connection.DeviceLink>();
            copy.add_all(_device_links);
            foreach (var dl in copy) {
                if (!dl.link_should_be_kept_alive()) {
                    _device_links.remove(dl);
                }
            }
        }

//         public string getLocalIpAddress();

        [Callback]
        public virtual bool send_packet(NetworkProtocol.Packet pkt)
                requires (pkt.packet_type != NetworkProtocol.PACKET_TYPE_PAIR)
                requires (is_paired())
        {
            if (pkt.packet_type in info.incoming) {
                //Maybe we could block here any packet that is not an identity or a pairing packet to prevent sending non encrypted data
                foreach (var dl in _device_links) {
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

            if (is_reachable()) {
                this.pairing_error(_("Device not reachable"));
                return;
            }

            foreach (var dl in _device_links) {
                dl.user_requests_pair();
            }
        }
        
        [Callback]
        public void unpair() { // from all links
            foreach (var dl in _device_links) {
                dl.user_requests_unpair();
            }
            Config.Config.instance().remove_paired_device(this.id);
            paired_changed(false);
        }
        
        [Callback]
        public void reload_plugins() {
            var engine = Plugin.PluginManager.instance().engine;
            Type tt = typeof(Plugin.Plugin);
            message("Extension set for interface: %s (%s)", tt.name(), tt.is_interface().to_string());
            _extension_set = new Peas.ExtensionSet(engine, typeof(Plugin.Plugin), "device", this);
            _extension_set.@foreach((ext_set, info, extension) => {
                (extension as Plugin.Plugin).name = info.get_name();
                var out_cap = new HashSet<string>();
                out_cap.add_all_array(info.get_external_data("X-Outgoing-Capabilities").split(","));
                (extension as Plugin.Plugin).outgoing_capabilities = out_cap;
                var in_cap = new HashSet<string>();
                in_cap.add_all_array(info.get_external_data("X-Incoming-Capabilities").split(","));
                (extension as Plugin.Plugin).incoming_capabilities = in_cap;
            });

            _extension_set.extension_added.connect((info, extension) => {
                debug("Extension added for interface %s from plugin: %s", typeof(Plugin.Plugin).name(), info.get_name() );
                (extension as Plugin.Plugin).activate();
            });
            _extension_set.extension_removed.connect((info, extension) => {
                (extension as Plugin.Plugin).deactivate();
            });
        }

        [Callback]
        public void accept_pairing() {
            if (_pair_requests.is_empty) {
                warning("No pair requests to accept!");
            }
            //copying because the pairing handler will be removed upon accept
            var copy = new Gee.HashSet<Connection.PairingHandler>();
            copy.add_all(_pair_requests);
            foreach (var ph in copy) {
                ph.accept_pairing();
            }
        }

        [Callback]
        public void reject_pairing() {
            if (_pair_requests.is_empty) {
                warning("No pair requests to accept!");
            }
            //copying because the pairing handler will be removed upon accept
            var copy = new Gee.HashSet<Connection.PairingHandler>();
            copy.add_all(_pair_requests);
            foreach (var ph in copy) {
                ph.reject_pairing();
            }
        }
        
        [Callback]
        public bool has_pairing_requests() {
            return !_pair_requests.is_empty;
        }

        public string icon_name() {
            return icon_for_status(true, false);
        }
        
        public string status_icon_name() {
            return icon_for_status(is_reachable(), is_paired());
        }

        /* Private methods */
        [Callback]
        private void private_received_packet(NetworkProtocol.Packet pkt)
            requires (pkt.packet_type != NetworkProtocol.PACKET_TYPE_PAIR)
        {
            if (is_paired()) {
                int treated = 0;
                // TODO: use a dictionary with incoming-capabilities instead
                _extension_set.@foreach((ext_set, info, extension) => {
                    if (pkt.packet_type in (extension as Plugin.Plugin).incoming_capabilities) {
                        (extension as Plugin.Plugin).receive(pkt);
                        treated += 1;
                    }
                });
                if (treated == 0) {
                    warning("Discarding unsupported packet %s for device %s.", pkt.packet_type, this.name);
                }
            } else {
                debug("Device %s not paired, ignoring packet %s", info.name, pkt.packet_type);
                unpair();
            }

        }
        
        [Callback]
        private void link_destroyed(GLib.Object o) {
            remove_link( (Connection.DeviceLink)o );
        }
        
        [Callback]
        private void pair_status_changed(Connection.DeviceLink device_link, Connection.DeviceLink.PairStatus status) {
            if (status == Connection.DeviceLink.PairStatus.NOT_PAIRED) {
                Config.Config.instance().remove_paired_device(this.id);

                foreach (var dl in _device_links) {
                    if (dl != device_link) {
                        dl.pair_status = Connection.DeviceLink.PairStatus.NOT_PAIRED;
                    }
                }
            } else {
                Config.Config.instance().add_paired_device(this.id, this.info);
            }

            reload_plugins(); // Will load/unload plugins

            bool is_trusted = (status == Connection.DeviceLink.PairStatus.PAIRED);
            paired_changed(is_trusted);
            assert(is_trusted == this.is_paired());
        }

        [Callback]
        private void add_pairing_request(Connection.PairingHandler handler) {
            bool was_empty = _pair_requests.is_empty;
            _pair_requests.add(handler);

            if (was_empty != _pair_requests.is_empty) {
                has_pairing_requests_changed(!_pair_requests.is_empty);
            }
        }

        [Callback]
        private void remove_pairing_request(Connection.PairingHandler handler) {
            bool was_empty = _pair_requests.is_empty;
            _pair_requests.remove(handler);

            if (was_empty != _pair_requests.is_empty) {
                has_pairing_requests_changed(!_pair_requests.is_empty);
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
