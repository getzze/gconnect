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

    [DBus (name="org.freedesktop.DBus.Properties")]
    public interface DbusPropIface : DBusProxy {
        public signal void properties_changed(string iface, HashTable<string,Variant> changed, string[] invalid);
    }

    [DBus (name = "org.bluez.Adapter1")]
    public interface BluezAdapter : DBusProxy {
        public abstract void start_discovery() throws DBusError, IOError;
        public abstract void set_discovery_filter(GLib.HashTable<string, GLib.Variant> properties) throws DBusError, IOError;
        public abstract void stop_discovery() throws DBusError, IOError;
        public abstract void remove_device(GLib.ObjectPath device) throws DBusError, IOError;
        public abstract string[] get_discovery_filters() throws DBusError, IOError;
        public abstract bool discoverable {  get; set; }
        public abstract uint discoverable_timeout {  get; set; }
        public abstract bool pairable {  get; set; }
        public abstract uint pairable_timeout {  get; set; }
        public abstract bool discovering {  get; }
        [DBus (name = "UUIDs")]
        public abstract string[] uuids { owned get; }
    }


    [DBus (name = "org.bluez.Device1")]
    public interface BluezDeviceBus : DBusProxy {
        public abstract async void connect_profile(string uuid) throws DBusError, IOError;
        public abstract async void disconnect_profile(string uuid) throws DBusError, IOError;

        public abstract string name { owned get; }
        public abstract bool connected { owned get; }
        public abstract bool paired { owned get; }
        [DBus (name = "UUIDs")]
        public abstract string[] uuids { owned get; }
    }

    [DBus (name = "org.bluez.ProfileManager1")]
    public interface BluezProfileManager : DBusProxy {
        public abstract void register_profile(ObjectPath profile, string uuid, HashTable<string, Variant> options) throws DBusError, IOError;
        public abstract void unregister_profile(ObjectPath profile) throws DBusError, IOError;
    }

    struct profile_data {
        DbusPropIface prop_iface;
        weak BluetoothSocketConnection conn;
        ulong signal_id;
    }

    [DBus(name = "org.bluez.Profile1")]
    private class BluezProfile : GLib.Object {
        private weak BluetoothLinkProvider provider;
        private HashTable<ObjectPath, profile_data?> sockets;
        
        public BluezProfile(BluetoothLinkProvider provider)
        {
            this.provider = provider;
            sockets = new HashTable<ObjectPath, profile_data?>(str_hash, str_equal);
        }
        
        ~BluezProfile()
        {
            var devices = sockets.get_keys();
            foreach (unowned ObjectPath device in devices) {
                try {
                    request_disconnection(device);
                } catch (GLib.Error e) {
                }
            }
        }
        
        public void release() throws GLib.Error {
            debug("Bluetooth service has been released.");
        }
        
        public void new_connection(ObjectPath device, GLib.Socket socket, HashTable<string, Variant> fd_properties) throws GLib.Error {
            var parts = device.split("/");
            var address = parts.length == 5
                ? "%s".printf(parts[4].substring(4).replace("_", ":")) : (string)device;
            debug("New bluetooth connection from %s (%d).", address, socket.fd);
            if (!sockets.contains(device)) {
                DbusPropIface device_props = null;
                try {
                    device_props = Bus.get_proxy_sync(BusType.SYSTEM, "org.bluez", device);
                } catch (Error e) {
                    warning("%s", e.message);
                    return;
                }
                if (device_props != null) {
                    device_props.properties_changed.connect(on_properties_changed);
                }

                var connection = new BluetoothSocketConnection(socket, address);
                var signal_id = connection.forced_close.connect(() => {
                    request_disconnection(device);
                });
                profile_data data = profile_data() {
                    conn=connection,
                    prop_iface=device_props,
                    signal_id=signal_id
                };
                
                sockets[device] = data;
                this.provider.incoming_connection.begin(connection);
            }
        }
        
        private void on_properties_changed (DbusPropIface sender, string iface, HashTable<string,Variant> changed, string[] invalid) {
            var path = new ObjectPath(sender.get_object_path());
            if (iface == "org.bluez.Device1" && changed.contains("Connected")) {
                bool connected = changed["Connected"].get_boolean();
                if (!connected) {
                    request_disconnection(path);
                }
            }
        }
        
        public void request_disconnection(ObjectPath device) throws GLib.Error {
            if (this.sockets.contains(device)) {
                var conn = sockets[device].conn;
                if (conn != null && conn is Object && !conn.is_closed()) {
                    var signal_id = sockets[device].signal_id;
                    if (signal_id > 0) {
                        conn.disconnect(signal_id);
                    }
                    conn.close();
                }
                var prop_iface = sockets[device].prop_iface;
                if (prop_iface != null && conn is Object) {
                    prop_iface.properties_changed.disconnect(on_properties_changed);
                }
                this.sockets.remove(device);
                debug("Bluetooth device disconnected: %s", device);
            }
        }
        
        public bool is_connected(ObjectPath device) throws DBusError, IOError {
            return this.sockets.contains(device);
        }

        public bool has_connected_devices() throws DBusError, IOError {
            return (this.sockets.length>0);
        }
    }

    string spd_record (string name, string uuid, uint8? channel = null, uint16? psm = null) {
        string template = """<?xml version="1.0" encoding="utf-8" ?>
<record>
    <attribute id="0x0001">
        <!-- ServiceClassIDList -->
        <sequence>
            <uuid value="%s" />      <!-- Custom UUID -->
            <uuid value="0x%s" />    <!-- Custom UUID hex for Android -->
            <uuid value="0x1101" />  <!-- SPP profile -->
        </sequence>
    </attribute>
    <attribute id="0x0003">
        <!-- ServiceID -->
        <uuid value="%s" />
    </attribute>
    <attribute id="0x0004">
        <!-- ProtocolDescriptorList -->
        <sequence>
            <sequence>
                <uuid value="0x0100" />
                %s
            </sequence>
            <sequence>
                <uuid value="0x0003" />
                %s
            </sequence>
        </sequence>
    </attribute>
    <attribute id="0x0005">
        <!-- BrowseGroupList -->
        <sequence>
            <uuid value="0x1002" />
        </sequence>
    </attribute>
    <attribute id="0x0009">
        <!-- ProfileDescriptorList -->
        <sequence>
            <uuid value="0x1101" />
        </sequence>
    </attribute>
    <attribute id="0x0100">
        <!-- Service name -->
        <text value="%s" />
    </attribute>
</record>""";

        string uuid128 = string.joinv("", uuid.split("-"));
        var channel_str = "";
        var psm_str = "";
        if (channel != null) {
            channel_str = """<uint8 value="%#x" /> <!-- RFCOMM channel -->""".printf(channel);
        }
        if (psm != null) {
            psm_str = """<uint8 value="%#x" /> <!-- RFCOMM channel -->""".printf(psm);
        }
        
        return template.printf(uuid, uuid128, uuid, channel_str, psm_str, name);
    }
} 
