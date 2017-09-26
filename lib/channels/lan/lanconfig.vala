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

namespace Gconnect.LanConnection {
    uint16[] get_list_uint16(Variant @value) {
        assert(@value.n_children() == 2);
        uint16 min = @value.get_child_value(0).get_uint16();
        uint16 max = @value.get_child_value(1).get_uint16();
        uint16[] ret = {min, max};
        return ret;
    }
    
    Variant set_list_uint16(uint16[] @value) {
        var min = new Variant.uint16(@value[0]);
        var max = new Variant.uint16(@value[1]);
        Variant[] arr = {min, max};
        return new Variant.tuple(arr);
    }
    
    public class LanLinkConfig : Connection.LinkConfig {
        private const string GSETTING_ID = "org.gconnect.providers.lan";
        private GLib.Settings settings;
        private string[] _ip_discovery;
        private uint16[] _tcp_range;
        private uint16[] _tcp_transfer_range;

        private Gee.ArrayList<string> known_ip_addresses;
        
        public string[] ip_discovery {
            get {
                _ip_discovery = this.settings.get_strv("ip-discovery");
                return _ip_discovery;
            }
            set {
                this.settings.set_strv("ip-discovery", value);
            }
        }

        public uint16 udp_port {
            get {
                return this.settings.get_value("udp-port").get_uint16();
            }
        }

        public uint16[] tcp_range {
            get {
                _tcp_range = get_list_uint16(this.settings.get_value("tcp-port-range"));
                return _tcp_range;
            }
        }
        
        public uint16[] tcp_transfer_range {
            get {
                _tcp_transfer_range = get_list_uint16(this.settings.get_value("tcp-file-transfer-port-range"));
                return _tcp_transfer_range;
            }
        }
        
        public LanLinkConfig() {
            known_ip_addresses = new Gee.ArrayList<string>();
            
            SettingsSchemaSource sss;
            SettingsSchema? schema;
            sss = SettingsSchemaSource.get_default();
            schema = sss.lookup(GSETTING_ID, true);
            if (schema != null) {
                this.settings = new Settings(GSETTING_ID);
            } else {
                string path = ".";
                warning("Look for compiled gschemas in the current directory: %s", path);
                try {
                    sss = new SettingsSchemaSource.from_directory(path, null, false);
                } catch (Error e) {
                    error("Compiled gschema not found in %s", path);
                }
                schema = sss.lookup(GSETTING_ID, false);
                if (schema == null) {
                    error("Gschema %s not found in %s", GSETTING_ID, path);
                }
                this.settings = new Settings.full(schema, null, null);
            }

            // Direct bindings do not work because the types are not compatible
            this.settings.changed["ip-discovery"].connect (() => {
                // Avoid double emission of property change
                if (_ip_discovery != this.settings.get_strv("ip-discovery")) {
                    this.notify_property("ip_discovery");
                }
            });
            this.settings.changed["udp-port"].connect (() => {
                this.notify_property("udp_port");
            });
            this.settings.changed["tcp-port-range"].connect (() => {
                this.notify_property("tcp_range");
            });
            this.settings.changed["tcp-file-transfer-port-range"].connect (() => {
                this.notify_property("tcp_transfer_range");
            });
            
//            debug("LanConfig loaded: %u, [%u-%u], %s", this.udp_port, this.tcp_range[0], this.tcp_range[1], string.joinv(",", this.ip_discovery));
        }

        public override void add_device(DeviceManager.Device dev) {
            string ip = dev.ip_address;
            if (ip != "" && ip in known_ip_addresses) {
                known_ip_addresses.add(ip);
            }
        }
        
        public override void remove_device(DeviceManager.Device dev) {
            string ip = dev.ip_address;
            if (ip != "" && ip in known_ip_addresses) {
                known_ip_addresses.remove(ip);
            }
        }

        public string[] get_known_ip_addresses() {
            return known_ip_addresses.to_array();
        }

        public void reset() {
            foreach (var key in this.settings.settings_schema.list_keys()) {
                this.settings.reset(key);
            }
        }
    }
}
