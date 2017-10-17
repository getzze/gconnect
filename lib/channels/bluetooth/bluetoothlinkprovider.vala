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
//using Posix;
// using Connection;
// using DeviceManager;
// using Config;

namespace Gconnect.BluetoothConnection {
    uint MIN_VERSION_WITH_GATT_SUPPORT = 8;

    public class BluetoothLinkProvider : Connection.LinkProvider {
        private const string PROFILE_PATH = "/org/gconnect/Profiles";
        private const string BLUETOOTH_KDE_UUID = "185f3df4-3268-4e3f-9fca-d4d5059915bd";
        private const string BLUETOOTH_SPP_UUID = "00001101-0000-1000-8000-00805f9b34fb";  // rfcomm
        
        // Public attributes
        private BluetoothLinkConfig _config;

        // Private attributes
        private string uuid;
        private BluezProfile profile;
        private BluezProfileManager profile_manager;
        private BluezAdapter adapter;
        private DBusObjectManager manager;
        private uint32 discovery_timeout = 30; // 30s
        private ObjectPath profile_path;
        private uint profile_id = 0;
        private uint connect_to_profile_timer = 0;
        private int reconnect_timeout;

        
        private HashMap<string, BluetoothConnection.BluetoothDeviceLink> links;

        private bool test_mode;

        public override Connection.LinkConfig config {
            get { return this._config; }
            protected set { this._config = value as BluetoothLinkConfig; }
        }

        public BluetoothLinkProvider(bool mode) throws Error {
            this._config = new BluetoothLinkConfig();
            this.test_mode = mode;
            this.uuid = BLUETOOTH_KDE_UUID;
            this.reconnect_timeout = 30;
            
            links = new HashMap<string, BluetoothConnection.BluetoothDeviceLink>();


        }
        
        // Public methods
        public override string name { get; protected set; default="BluetoothLinkProvider"; }
        public override int priority { get; protected set; default=PRIORITY_HIGH; }
        
        public override void on_start() throws Error {
            info("BluetoothLinkProvider on start ...");

            if (this.profile_manager == null) {
                this.profile_manager = Bus.get_proxy_sync(BusType.SYSTEM, "org.bluez", "/org/bluez");
            }

            if (profile != null) {
                return;
            }

            uint16? psm = null;
            uint8? channel = null;
//            uint8? channel = 1;
            
            this.profile = new BluezProfile(this);
            var options = new HashTable<string, Variant>(str_hash, str_equal);
            options.insert("Name", new Variant.string("gconnect"));
//            options.insert("Service", new Variant.string("spp char BLUETOOTH_KDE_UUID"));
            options.insert("RequireAuthentication", new Variant.boolean(true));
            options.insert("RequireAuthorization", new Variant.boolean(false));
            options.insert("AutoConnect", new Variant.boolean(true));
            if (channel != null) {
                options.insert("Channel", new Variant.uint16(channel));
            }    
            if (psm != null) {
                options.insert("PSM", new Variant.uint16(psm));
            }
            options.insert("ServiceRecord", new Variant.string(spd_record("gconnect", this.uuid, channel, psm)));
            this.profile_path = new ObjectPath(PROFILE_PATH);

            try {
                var conn = Bus.get_sync(BusType.SYSTEM, null);
                
                this.profile_id = conn.register_object(this.profile_path, this.profile);
//                options.@set("Role", new Variant.string("client"));
                this.profile_manager.register_profile(this.profile_path, this.uuid, options);
            } catch (Error e) {
                warning("%s", e.message);
            }

            this.manager = new DBusObjectManagerClient.for_bus_sync(BusType.SYSTEM, DBusObjectManagerClientFlags.NONE, "org.bluez", "/", null, null);
            // check interfaces added dynamically
            this.manager.interface_added.connect(interface_added);
            this.manager.interface_removed.connect(interface_removed);
            
            this.on_network_change();
        }

        public override void on_stop() {
            info("BluetoothLinkProvider on stop ...");
            if (this.profile != null) {
                this.profile_manager.unregister_profile(this.profile_path);
                Bus.get_sync(BusType.SYSTEM, null).unregister_object(this.profile_id);
                this.profile = null;
                this.profile_path = null;
                this.profile_id = 0;
            }
        }

        public override void on_network_change() {
            handle_managed_objects();
        }

        // Private methods
        private async void handle_managed_objects() {
            var objects = this.manager.get_objects();

            foreach (DBusObject o in objects) {
                foreach (DBusInterface iface in o.get_interfaces()) {
                    connect_interface(o, iface);
                }
            }

            if (!this.profile.has_connected_devices()) {
                // try to connect to the paired device every few seconds
                connect_to_profile_timer = Timeout.add_seconds(reconnect_timeout, on_try_to_connect_devices);
            }
        }

        private bool on_try_to_connect_devices() {
            connect_to_profile_timer = 0;
            handle_managed_objects();
            return false;  // Stop timer
        }

        private void connect_interface(DBusObject object, DBusInterface iface) {
            if (!(iface is DBusProxy)) {
                return;
            }

            var name = (iface as DBusProxy).get_interface_name();
            var path = new ObjectPath(object.get_object_path());

            // try to get the device
            if (name == "org.bluez.Adapter1") {
//                this.adapter = Bus.get_proxy_sync(BusType.SYSTEM, "org.bluez", path);
//                this.adapter.discoverable_timeout = this.discovery_timeout;
//                this.adapter.stop_discovery();
//                this.adapter.start_discovery();
//                this.adapter.stop_discovery();
//                debug("Start discovering bluetooth devices for %us ...", this.discovery_timeout);
            }

            if (name == "org.bluez.Device1" && !this.profile.is_connected(path)) {
                BluezDeviceBus device = null;
                try {
                    device = Bus.get_proxy_sync(BusType.SYSTEM, "org.bluez", path);
                } catch (Error e) {
                    warning("%s", e.message);
                }

                if (device != null && device.paired && device.connected) {
                    if (!(BLUETOOTH_KDE_UUID in device.uuids || BLUETOOTH_SPP_UUID in device.uuids )) {
                        debug("Target service %s not in device uuids:\n%s", this.uuid, string.joinv("\n", device.uuids));
                        return;
                    }
                    debug("Try connecting device: %s", device.name);
                    try {
                        device.connect_profile.begin(this.uuid);
                    } catch (Error e) {
                        warning("Error connecting to device '%s': %s", device.name, e.message);
                    }
                }
            }
        }

        private void interface_added(DBusObjectManager manager, DBusObject object, DBusInterface iface) {
            connect_interface(object, iface);
        }

        private void interface_removed(DBusObjectManager manager, DBusObject object, DBusInterface iface) {
            debug("removed: [%s]\n", object.get_object_path());
            debug("  %s\n", iface.get_info().name);
        }

        internal async void incoming_connection(BluetoothSocketConnection conn) {
            debug("Start new socket connection");

            // If network is on ssl, do not believe when they are connected, believe when handshake is completed
            bool res = false;
            var new_pkt = new NetworkProtocol.Packet.identity();
            try {
                string sent = new_pkt.serialize() + "\n";
                res = conn.write(sent);
                debug("Identity packet sent: %s", sent);
            } catch (IOError e) {
                warning("Error with tcp client connection: %s\n", e.message);
                conn.close();
                return;
            }
            
            
            string req = null;
            try {
                req = conn.read_line();
            } catch (Error e) {
                warning("Error with server connection: %s\n", e.message);
                conn.close();
                return;
            }   
            if (req == null) {
                conn.close();
                return;
            }
            debug("BluetoothLinkProvider received reply: %s", req);
            
            NetworkProtocol.Packet pkt = null;
            try {
                pkt = NetworkProtocol.Packet.unserialize(req);
            } catch (NetworkProtocol.PacketError e) {
                warning("Error unserializing json packet %s", req);
                conn.close();
                return;
            }
            if (pkt.packet_type != NetworkProtocol.PACKET_TYPE_IDENTITY) {
                warning("BluetoothLinkProvider response: Expected identity, received %s", pkt.packet_type);
                conn.close();
                return;
            }
            var device_id = pkt.get_device_id();
            add_link(device_id, conn, pkt);
        }
        
        private void device_link_destroyed(string id) {
            links.unset(id);
        }
    
        // Private methods
        private void add_link(string device_id, BluetoothSocketConnection conn,
                                NetworkProtocol.Packet pkt) {
            debug("Add link to device: %s", device_id);

            if (links.has_key(device_id)) {
                debug("device_link already existed, resetting it.");
                links[device_id].reset(conn);
            } else {
                var new_dl = new BluetoothDeviceLink(device_id, this, conn);
                assert(new_dl != null);
                debug("New device_link created");
                new_dl.destroyed.connect(device_link_destroyed);
                links[device_id] = new_dl;
                assert(links[device_id] != null);
            }
            on_connection_received(pkt, links[device_id]);
        }
    }
} 
