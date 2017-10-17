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

namespace Gconnect.BluetoothConnection {

    public class BluetoothLinkConfig : Connection.LinkConfig {
        private const string GSETTING_ID = "org.gconnect.providers.bluetooth";
        private GLib.Settings settings;

        private Gee.ArrayList<string> known_ip_addresses;
        
        public BluetoothLinkConfig() {
            
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
        }

        public void reset() {
            foreach (var key in this.settings.settings_schema.list_keys()) {
                this.settings.reset(key);
            }
        }
    }
}
