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
// using Connection;
// using DeviceManager;
// using Config;

namespace Gconnect.Core {
    
    Core __instance = null;

    struct CorePrivateDict {
        // Connections
        public HashSet<Connection.LinkProvider> link_providers;
        
        // Devices
        public HashMap<string, DeviceManager.Device> devices;

        // Discovery modes
        public HashSet<string> discovery_mode_acquisitions;
    }

    [DBus(name = "gconnect.core")]
    public class Core: GLib.Object {
        private static Core? _instance = null;
        
        private CorePrivateDict _dict;
        
        public signal void device_visibility_changed(string id, bool visible);
        public signal void announced_name_changed(string name);
        public signal void pairing_requests_changed(bool has_requests);
        public signal void device_added(string id);
        public signal void device_removed(string id);

        // Virtual methods, can be overridden because it requires user input.
        // For a CLI daemon, use libinput. For a GUI; use notifications.
        public virtual void ask_pairing_confirmation(string device_id) {
            var list = Config.Config.instance().get_auto_pair_devices();
            bool trusted = false;
            foreach (string id in list) {
                if (id==device_id) {
                    trusted = true;
                    break;
                }
            }
            // Accept/reject pairing
            DeviceManager.Device device = get_device(device_id);
            if (trusted) {
                debug("Device id found in auto-pair device list. Accept pairing with device %s (id:%s)", device.name, device.id);
                device.accept_pairing();
            }else{
                debug("Device id not found in auto-pair device list. Reject pairing with device %s (id:%s)", device.name, device.id);
                device.reject_pairing();
            }
        }

        public virtual void report_error(string title, string description) {
            error("A core error was reported: %s -> %s", title, description);
        }

        
        public Core (bool test = true) {
            // Load backends
            if (test) {
                this._dict.link_providers.add(new LoopbackConnection.LoopbackLinkProvider());
            } else {
                #if GCONNECT_LAN
                    this._dict.link_providers.add(new Connection.LanLinkProvider());
                #endif
                #if GCONNECT_BLUETOOTH
                    this._dict.link_providers.add(new Connection.BluetoothLinkProvider());
                #endif
            }
            
            // Get known paired devices
            var list = Config.Config.instance().get_paired_devices();
            foreach (string device_id in list) {
                this.add_device(new DeviceManager.Device.from_id(this, device_id));
            }

            // Discover new devices
            foreach (var lp in this._dict.link_providers) {
                lp.on_connection_received.connect(this.on_new_device_link);
                lp.on_start();
            }

            debug("Gconnect core started.");
        }
        
        public static Core instance() {
            if (__instance == null) {
                var core = new Core();
                __instance = core;
            }
            return __instance;
//             if (Core._instance == null) {
//                 var core = new Core();
//                 Core._instance = core;
//             }
//             return Core._instance;
        }

        [Callback]
        public void acquire_discovery_mode(string key) {
            bool old_state = this._dict.discovery_mode_acquisitions.size==0;

            this._dict.discovery_mode_acquisitions.add(key);

            if (old_state != (this._dict.discovery_mode_acquisitions.size==0) ) {
                this.force_on_network_change();
            }
        }

        [Callback]
        public void release_discovery_mode(string key) {
            bool old_state = this._dict.discovery_mode_acquisitions.size==0;

            this._dict.discovery_mode_acquisitions.remove(key);

            if (old_state != (this._dict.discovery_mode_acquisitions.size==0) ) {
                this.clean_devices();
            }
        }
        
        private void remove_device(DeviceManager.Device device) {
            string id = device.id;
            this._dict.devices.unset(device.id);
            this.device_removed(id);
        }

        private void clean_devices() {
            foreach (var device in this._dict.devices.values) {
                if (device.is_paired()) {
                    continue;
                }
                device.clean_unneeded_links();
                // Remove device if it is not connected anymore
                if (!device.is_reachable()) {
                    this.remove_device(device);
                }
            }
        }
        
        [Callback]
        public void force_on_network_change() {
            debug("Sending onNetworkChange to %d LinkProviders.", this._dict.link_providers.size);
            foreach (var lp in this._dict.link_providers) {
                lp.on_network_change();
            }
        }

        [DBus (visible = false)]
        public DeviceManager.Device? get_device(string device_id) {
            foreach (var device in this._dict.devices.values) {
                if (device.id == device_id) {
                    return device;
                }
            }
            return null;
        }

        [Callback]
        public string[] devices(bool only_reachable, bool only_paired) {
            string[] ret = {};
            foreach (var device in this._dict.devices.values) {
                if (only_reachable && !device.is_reachable()) continue;
                if (only_paired    && !device.is_paired()) continue;
                ret += device.id;
            }
            return ret;
        }

        [Callback]
        private void on_new_device_link(NetworkProtocol.Packet identity_packet, Connection.DeviceLink dl) {
            string id = identity_packet.get_string("device_id");
            string name = identity_packet.get_string("device_name");
            DeviceManager.Device device = null;
            debug("Device discovered %s via %s", id, dl.provider().name);

            if (this._dict.devices.has_key(id)) {
                debug("It is a known device: %s", name);
                device = this._dict.devices[id];
                bool was_reachable = device.is_reachable();
                device.add_link(identity_packet, dl);
                if (!was_reachable) {
                    this.device_visibility_changed(id, true);
                }
            } else {
                debug("It is a new device: %s", name);
                device = new DeviceManager.Device.from_link(this, identity_packet, dl);

                // we discard the connections that we created but it's not paired.
                if (is_discovering_devices() || device.is_paired() || dl.link_should_be_kept_alive()) {
                    this.add_device(device);
                }
            }
        }

        [Callback]
        private void on_device_status_changed(DeviceManager.Device device) {
            debug("Device %s status changed. Reachable: %s. Paired: %s", device.name, (device.is_reachable())?"true":"false", (device.is_paired())?"true":"false");

            if (!device.is_reachable() && !device.is_paired()) {
                debug("Removing device: %s", device.name);
                this.remove_device(device);
            } else {
                this.device_visibility_changed(device.id, device.is_reachable());
            }

        }

        public void set_announced_name(string name) {
            debug("Change announcing name.");
            Config.Config.instance().set_name(name);
            this.force_on_network_change();
            this.announced_name_changed(name);
        }

        public string get_announced_name() {
            return Config.Config.instance().get_name();
        }

        private bool is_discovering_devices()
        {
            return !(this._dict.discovery_mode_acquisitions.size==0);
        }

        [Callback]
        public string device_id_by_name(string name) {
            foreach (var device in this._dict.devices.values) {
                if (device.name == name && device.is_paired()) {
                    return device.id;
                }
            }
            return "";
        }

        private void add_device(DeviceManager.Device device) {
            string id = device.id;
            device.reachable_changed.connect((d, b) => this.on_device_status_changed(d));
            device.paired_changed.connect((d, b) => this.on_device_status_changed(d));
            device.has_pairing_requests_changed.connect((d, has_requests) => this.pairing_requests_changed(has_requests));
            device.has_pairing_requests_changed.connect((d, has_requests) => {
                if (has_requests) {
                    this.ask_pairing_confirmation(d.id);
                }
            });
            this._dict.devices[id] = device;

            this.device_added(id);
        }

        public string[] pairing_requests() {
            string[] ret = {};
            foreach (var device in this._dict.devices.values) {
                if (device.has_pairing_requests()) {
                    ret += device.id;
                }
            }
            return ret;
        }

        public string self_id() {
            return Config.Config.instance().device_id();
        }
    }
}

