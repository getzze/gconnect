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

namespace core {
    
    struct CorePrivate
    {
        // Connections
        public HashSet<Connection.LinkProvider> link_providers;
        
        // Devices
        public HashMap<string, DeviceManager.Device> devices;

        // Discovery modes
        public HashSet<string> discovery_mode_acquisitions;
    };

    [DBus(name = "gconnect.core")]
    public class Core: GLib.Object {
        private static Core? _instance = null;
        
        private CorePrivate _dict;
        
        public signal device_visibility_changed(string id, bool visible);
        public signal announced_name_changed(string name);
        public signal pairing_requests_changed(bool has_requests);
        public signal device_added(string id);
        public signal device_removed(string id);

        // Virtual methods, can be overridden because it requires user input.
        // For a CLI daemon, use libinput. For a GUI; use notifications.
        public virtual void ask_pairing_confirmation(DeviceManager.Device device) {
            var list = Config.Config.instance().auto_pair_devices();
            bool trusted = false;
            foreach (string device_id in list) {
                if (device.id==device_id) {
                    trusted = true;
                    break;
                }
            }
            if (trusted) {
                debug("Device id found in auto-pair device list. Accept pairing with device %s (id:%s)", device.name, device.id);
                device.accept_pairing();
            }else{
                debug("Device id not found in auto-pair device list. Reject pairing with device %s (id:%s)", device.name, device.id);
                device.reject_pairing();
            }
        };

        public virtual void report_error(string title, string description) {
            error("A core error was reported: %s -> %s", title, description);
        }

        
        public Core (GLib.Object parent, bool test) {
            this._dict = new CorePrivate;
            // Load backends
            if (test) {
                this._dict.link_providers.add(new Connection.LoopbackLinkProvider());
            } else {
                this._dict.link_providers.add(new Connection.LanLinkProvider());
                #if GCONNECT_BLUETOOTH
                    this._dict.link_providers.add(new Connection.BluetoothLinkProvider());
                #endif
            }
            
            // Get known paired devices
            var list = Config.Config.instance().paired_devices();
            foreach (string device_id in list) {
                this.add_device(new DeviceManager.Device(this, device_id));
            }

            // Discover new devices
            foreach (var lp in this._dict.link_providers) {
                lp.onConnectionReceived.connect(this.on_new_device_link);
                lp.on_start();
            }

            debug("Gconnect core started.");
        }
        
        public static Core? instance() {
            if (Core._instance == null) {
                var core = new Core();
                Core._instance = core;
            }
            return Core._instance;
        }

        public void acquire_discovery_mode(string key) {
            bool old_state = this._dict.discovery_mode_acquisitions.size==0;

            this._dict.discovery_mode_acquisitions.add(key);

            if (old_state != this._dict.discovery_mode_acquisitions.size==0)) {
                this.force_on_network_change();
            }
        }

        public void release_discovery_mode(string key) {
            bool old_state = this._dict.discovery_mode_acquisitions.size==0;

            this._dict.discovery_mode_acquisitions.remove(key);

            if (old_state != this._dict.discovery_mode_acquisitions.size==0)) {
                this.clean_devices();
            }
        }
        
        private void remove_device(DeviceManager.Device device) {
            string id = device.id;
            this._dict.devices.remove(device.id);
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
        
        public void force_on_network_change() {
            debug("Sending onNetworkChange to %d LinkProviders.", this._dict.link_providers.size);
            foreach (var lp in this._dict.link_providers) {
                lp.on_network_change();
            }
        }

        public DeviceManager.Device? get_device(string device_id) {
            foreach (var device in this._dict.devices.values) {
                if (device.id == device_id) {
                    return device;
                }
            }
            return null;
        }

        public string[] devices(bool only_reachable, bool only_paired) {
            string[] ret = {};
            foreach (var device in this._dict.devices.values) {
                if (only_reachable && !device.is_reachable()) continue;
                if (only_paired    && !device.is_paired()) continue;
                ret += device.id;
            }
            return ret;
        }

        private void on_new_device_link(Packet identity_packet, Connection.DeviceLink dl) {
            string id = identity_packet.get<string>("device_id");

            debug("Device discovered %s via %s", id, dl.provider().name());

            if (this._dict.devices.has_key(id)) {
                debug("It is a known device: %s", identity_package.get<string>("device_name"));
                var device = this._dict.devices[id];
                bool was_reachable = device.is_reachable();
                device.add_link(identity_package, dl);
                if (!was_reachable) {
                    this.device_visibility_changed(id, true);
                }
            } else {
                debug("It is a new device: %s", identity_package.get<string>("device_name"));
                var device = new Device(this, identity_package, dl);

                //we discard the connections that we created but it's not paired.
                if (!is_discovering_devices() && !device.is_paired() && !dl.link_should_be_kept_alive()) {
                    delete device;
                } else {
                    this.add_device(device);
                }
            }
        }

        private void on_device_status_changed(DeviceManager.Device device) {
            debug("Device %s status changed. Reachable: %s. Paired: %s", device.name, (device.is_reachable())?"true":"false", (device->is_paired())?"true":"false");

            if (!device.is_reachable() && !device.is_paired()) {
                debug("Removing device: %s", device.name);
                this.remove_device(device);
            } else {
                this.device_visibility_changed(device.id, device.is_reachable());
            }

        }

        public void set_announced_name(string name) {
            debug("Change announcing name.";
            Config.Config.instance().set_name(name);
            this.force_on_network_change();
            this.announced_name_changed(name);
        }

        public string get_announced_name() {
            return Config.Config.instance().name();
        }

        private bool is_discovering_devices()
        {
            return !(this._dict.discovery_mode_acquisitions.size==0);
        }

        public string device_id_by_name(string name) {
            foreach (var device in this._dict.devices.values) {
                if (device.name == name && device.is_paired()) {
                    return device.id;
                }
            }
            return {};
        }

        private void add_device(DeviceManager.Device device) {
            string id = device.id;
            device.reachable_changed.connect((d) => this.on_device_status_changed(d));
            device.paired_changed.connect((d) => this.on_device_status_changed(d));
            device.has_pairing_requests_changed.connect(this.pairing_requests_changed);
            device.has_pairing_requests_changed.connect((d, has_requests) => {
                if (has_requests) {
                    this.ask_pairing_confirmation(d);
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

