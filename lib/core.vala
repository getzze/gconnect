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

    [Flags]
    public enum TestMode {
        LOOPBACK,
        LAN,
        BLUETOOTH
//        NONE = 0,
//        LOOPBACK = 1,
//        LAN = 2,
//        BLUETOOTH = 4
    }

    [DBus(name = "org.gconnect.core")]
    public class Core: GLib.Object {
        // Connections
        private HashSet<Connection.LinkProvider> link_providers;
        // Devices
        private HashMap<string, DeviceManager.Device> devices;
        // Discovery modes
        private HashSet<string> discovery_mode_acquisitions;
        // Configuration
        private Config.Config config;

        private unowned DBusConnection conn;
        private uint bus_name_id = 0;
        private uint bus_id = 0;
        
        public signal void device_visibility_changed(string id, bool visible);
        public signal void announced_name_changed(string name);
        public signal void pairing_requests_changed(bool has_requests);
        public signal void device_added(string id);
        public signal void device_removed(string id);

        // Virtual methods, can be overridden because it requires user input.
        // For a CLI daemon, use libinput. For a GUI; use notifications.
        public virtual void ask_pairing_confirmation(string device_id) {
            var list = this.config.get_auto_pair_devices();
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
            warning("A core error was reported: %s -> %s", title, description);
        }

        
        protected Core (TestMode test_mode = 0) {
            this.link_providers = new HashSet<Connection.LinkProvider>();
            this.devices = new HashMap<string, DeviceManager.Device>();
            this.discovery_mode_acquisitions = new HashSet<string>();
            this.config = Config.Config.instance();
            
            // Register on DBus
            this.bus_name_id = Bus.own_name (BusType.SESSION, "org.gconnect.core",
								   BusNameOwnerFlags.NONE, 
//								   BusNameOwnerFlags.ALLOW_REPLACEMENT
//                                   | BusNameOwnerFlags.REPLACE,
                                   on_bus_acquired, 
								   on_bus_name_acquired, 
                                   on_bus_name_lost);

            // Load backends
            if (TestMode.LOOPBACK in test_mode) {
                this.link_providers.add(new LoopbackConnection.LoopbackLinkProvider());
            }
#if GCONNECT_LAN
            this.link_providers.add(new LanConnection.LanLinkProvider(TestMode.LAN in test_mode));
#endif
#if GCONNECT_BLUETOOTH
            this.link_providers.add(new BluetoothConnection.BluetoothLinkProvider(TestMode.BLUETOOTH in test_mode));
#endif
        }            
        
        ~Core () {
            this.close();
        }
        
        private void init_core() {
            // Register Core on dbus
			try	{
                string path = this.dbus_path();
                this.bus_id = (uint)conn.register_object(path, this);
			} catch (IOError e) {
				warning ("Could not register objects: %s", e.message);
			}

            // Get known paired devices and connect on dbus
            var list = this.config.get_paired_devices();
            debug("Add already paired devices: %s", string.joinv("; ", list));
            foreach (string device_id in list) {
                this.add_device(new DeviceManager.Device.from_id(device_id));
            }

            // Discover new devices
            foreach (var lp in this.link_providers) {
                lp.on_connection_received.connect(this.on_new_device_link);
                lp.on_start();
            }

            // Change displayed name
            this.config.notify["device-name"].connect((s,p) => {
                this.force_on_network_change();
                this.announced_name_changed(this.config.device_name);
            });
            
            debug("Gconnect core started.");
        }

        
        public static Core instance() {
            if (__instance == null) {
                var core = new Core();
                __instance = core;
            }
            return __instance;
        }

        [DBus (visible = false)]
        public string dbus_path() { return "/modules/gconnect";}

        [Callback]
        public void acquire_discovery_mode(string key) {
            bool old_state = this.discovery_mode_acquisitions.size==0;

            this.discovery_mode_acquisitions.add(key);

            if (old_state != (this.discovery_mode_acquisitions.size==0) ) {
                this.force_on_network_change();
            }
        }

        [Callback]
        public void release_discovery_mode(string key) {
            bool old_state = this.discovery_mode_acquisitions.size==0;

            this.discovery_mode_acquisitions.remove(key);

            if (old_state != (this.discovery_mode_acquisitions.size==0) ) {
                this.clean_devices();
            }
        }
        
        private void remove_device(DeviceManager.Device device) {
            string id = device.id;
            // Unpublish from DBus
            device.unpublish();
            
            foreach (var provider in link_providers) {
                if (provider.name == "LanLinkProvider") {
                    provider.config.remove_device(device);
                    break;
                }
            }
            
            this.devices.unset(device.id);
            this.device_removed(id);
        }

        private void clean_devices() {
            foreach (var device in this.devices.values) {
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
            debug("Sending onNetworkChange to %d LinkProviders.", this.link_providers.size);
            foreach (var lp in this.link_providers) {
                lp.on_network_change();
            }
        }

        [DBus (visible = false)]
        public DeviceManager.Device? get_device(string device_id) {
            foreach (var device in this.devices.values) {
                if (device.id == device_id) {
                    return device;
                }
            }
            return null;
        }

        [Callback]
        public string[] list_devices(bool only_reachable, bool only_paired) {
            string[] ret = {};
            foreach (var device in this.devices.values) {
                if (only_reachable && !device.is_reachable()) continue;
                if (only_paired    && !device.is_paired()) continue;
                ret += device.id;
            }
            return ret;
        }

        [Callback]
        private void on_new_device_link(NetworkProtocol.Packet identity, Connection.DeviceLink dl) {
            string id = identity.get_device_id();
            DeviceManager.Device device = null;
            info("Device discovered %s via %s:\n%s", id, dl.provider.name, identity.to_string());

            if (this.devices.has_key(id)) {
                debug("It is a known device: %s", id);
                device = this.devices[id];
                bool was_reachable = device.is_reachable();
                device.update_info(identity);
                device.add_link(dl);
                if (!was_reachable) {
                    this.device_visibility_changed(id, true);
                }
            } else {
                debug("It is a new device: %s", id);
                device = new DeviceManager.Device.from_link(identity, dl);

                // we discard the connections that we created but it's not paired.
                if (is_discovering_devices() || device.is_paired() || dl.link_should_be_kept_alive()) {
                    this.add_device(device);
                } else {
                    debug("Device %s discarded because not in discovery mode, device is not paired and the link should not be kept alive.", device.id);
                }
            }
        }

        [Callback]
        private void on_device_status_changed(DeviceManager.Device device) {
            debug("Device %s status changed. Reachable: %s. Paired: %s", device.name, device.is_reachable().to_string(), device.is_paired().to_string());

            if (!device.is_reachable() && !device.is_paired()) {
                debug("Removing device: %s", device.name);
                this.remove_device(device);
            } else {
                this.device_visibility_changed(device.id, device.is_reachable());
            }

        }

        public void set_announced_name(string name) {
            debug("Change announcing name.");
            this.config.device_name = name;
            this.force_on_network_change();
            this.announced_name_changed(name);
        }

        public string get_announced_name() {
            return this.config.device_name;
        }

        private bool is_discovering_devices()
        {
            return !(this.discovery_mode_acquisitions.size==0);
        }

        [Callback]
        public string device_id_by_name(string name) {
            foreach (var device in this.devices.values) {
                if (device.name == name && device.is_paired()) {
                    return device.id;
                }
            }
            return "";
        }

        private void add_device(DeviceManager.Device device) {
            string id = device.id;
            message("Add device %s to list of available devices", id);
            device.reachable_changed.connect((d, b) => this.on_device_status_changed(d));
            device.paired_changed.connect((d, b) => this.on_device_status_changed(d));
            device.has_pairing_requests_changed.connect((d, has_requests) => this.pairing_requests_changed(has_requests));
            device.has_pairing_requests_changed.connect((d, has_requests) => {
                if (has_requests) {
                    this.ask_pairing_confirmation(d.id);
                }
            });
            // Publish on DBus
            device.publish(this.conn);

            foreach (var provider in link_providers) {
                if (provider.name == "LanLinkProvider") {
                    provider.config.add_device(device);
                    break;
                }
            }

            this.devices[id] = device;
            assert(this.devices[id] != null);
            debug("Device %s added.", id);
            
            this.device_added(id);
            
//            device.reload_plugins();
        }

        public string[] pairing_requests() {
            string[] ret = {};
            foreach (var device in this.devices.values) {
                if (device.has_pairing_requests()) {
                    ret += device.id;
                }
            }
            return ret;
        }

        public string self_id() {
            return this.config.device_id;
        }
        
        /* DBus was acquired, register plugin objects */
		private void on_bus_acquired (DBusConnection conn) {
			this.conn = conn;
		}
		
		private void on_bus_name_acquired (DBusConnection conn, string name) {
			message("DBus server started with bus name '%s'.", name);
            init_core();
		}
		
		private void on_bus_name_lost (DBusConnection conn, string name) {
			error("Could not aquire name '%s'\n", name);
        }
        
        private void unpublish () {
            // Unpublish devices
            foreach (var device in this.devices.values) {
                device.unpublish();
            }
            // Unpublish core
            this.conn.unregister_object(bus_id);
        }

        /* should be a destructor, but '~Core()' never gets called? */
		[DBus (visible = false)]
        public void close () {
			debug("Try to close DBus connection.");
            this.unpublish();
            
			Bus.unown_name(bus_name_id);
			try {
				this.conn.close_sync ();
				message("DBus server stopped.");
			}
			catch (Error e) {
				debug ("Error closing DBus connection: %s\n", e.message);
			}
            
            __instance = null;
        }
    }
}

