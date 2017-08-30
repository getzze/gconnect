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
// using Config;
// using Connection;
// using DeviceManager;
// using Config;

namespace Gconnect.Plugin {
    public interface Plugin : GLib.Object {
        /* Unowned (weak) reference to the Device */
        public abstract unowned DeviceManager.Device device { get; construct set; }

        /* Send a request packet */
        public virtual bool request(NetworkProtocol.Packet pkt) {
            return this.device.send_packet(pkt);
        }

        /* Treat a received packet */
        public abstract void receive(NetworkProtocol.Packet np);

        /* DBus path */
        public virtual string? dbus_path() { return null; }

        /* The "constructor" */
        public abstract void activate();

        /* The "destructor" */
        public abstract void deactivate();
    }

    [DBus(name = "org.gconnect.pluginmanager")]
    public class PluginManager : GLib.Object { 
        private static PluginManager _instance = null;
        
        private Gee.ArrayList<string> extra_paths { get; set;}

        public string[] outgoing_capabilities {
            owned get {
                var plugins_types = new Gee.HashSet<string> ();
                foreach (Peas.PluginInfo plugin in engine.get_plugin_list()) {
                    if (plugin.is_loaded()) {
                        plugins_types.add(plugin.get_external_data("X-Outgoing-Capabilities"));
                    }
                };
                return plugins_types.to_array();
            }
            private set {}
        }

        public string[] incoming_capabilities {
            owned get {
                var plugins_types = new Gee.HashSet<string> ();
                foreach (Peas.PluginInfo plugin in engine.get_plugin_list()) {
                    if (plugin.is_loaded()) {
                        plugins_types.add(plugin.get_external_data("X-Incoming-Capabilities"));
                    }
                };
                return plugins_types.to_array();
            }
            private set {}
        }

        public string dbus_path() { return "/modules/gconnect/plugins/"; }

        [DBus (visible = false)]
        public Peas.Engine engine { get; private set;}

        public PluginManager() {
            /* Get the default engine */
            this.engine = Peas.Engine.get_default();

            /* Enable the python3 loader */
            this.engine.enable_loader("python3");

            this.extra_paths = new Gee.ArrayList<string>();
            
            /* Add path to look for plugins */
            foreach (var path in plugins_paths()) {
                if (path!=null) {
                    debug("Look for plugins in directory: %s", path);
                    this.engine.add_search_path(path, path);
                }
            }
        
            bool ok;
            /* Load all the plugins */
            foreach (var plugin in this.engine.get_plugin_list()) {
//                 debug ("Try to load plugin: %#s \t %#s", plugin.get_name (), plugin.get_description () );
                ok = this.engine.try_load_plugin(plugin);
                if (ok) {
                    debug ("Plugin loaded: %#s", plugin.get_name ());
                } else {
                    info ("Could not load plugin: %#s", plugin.get_name ());
                }
            };
        }

        public static PluginManager instance() {
            if (PluginManager._instance==null) {
                var pm = new PluginManager();
                PluginManager._instance = pm;
            }
            return PluginManager._instance;
        }
        
        private string[] plugins_paths() {
            string[] paths = extra_paths.to_array();

            /* Add generic plugin path */
            paths += Config.Config.get_plugins_local_dir();
            paths += Config.Config.get_plugins_global_dir();

            /* Add current dir (comment if not debug) */
            if (true) {
                string current_path = Path.build_filename(Environment.get_current_dir(), "/plugins");
                paths += current_path;
            }
            return paths;
        }
        
        private Peas.PluginInfo? get_plugin(string name) {
            return engine.get_plugin_info (name);
        }

        public bool load_plugin (string name) {
            var plugin = get_plugin (name);
            if (plugin == null) {
                warning ("Plugin Not found");
                return false;
            };
            return engine.try_load_plugin(plugin);
        }

        public bool unload_plugin (string name) {
            var plugin = get_plugin (name);
            if (plugin == null) {
                warning ("Plugin Not found");
                return false;
            }
            return engine.try_unload_plugin(plugin);
        }

        private Gee.HashSet<Peas.PluginInfo> match_plugin (string incoming, string outgoing) {
            var ret = new Gee.HashSet<Peas.PluginInfo>();
            foreach (Peas.PluginInfo plugin in engine.get_plugin_list()) {
                if (plugin.is_loaded() && 
                    plugin.get_external_data("X-Incoming-Capabilities")==incoming &&
                    plugin.get_external_data("X-Outgoing-Capabilities")==outgoing) {
                    /* Only single match */
                    ret.add(plugin);
                }
            };
            return ret;
        }
    }
}
