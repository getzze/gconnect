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

using Notify;
using Gee;

namespace Gconnect {

    CoreDaemon __instance = null;
    
    public class CoreDaemon: Core.Core {
        private Gee.HashMap<int, Notify.Notification> notifications = new Gee.HashMap<int, Notify.Notification>();
        
        public static new CoreDaemon instance() {
            if (__instance == null) {
                var core = new CoreDaemon();
                __instance = core;
            }
            return __instance;
        }
        
        public new void close () {
           base.close();
           __instance = null; 
        }

        public override void ask_pairing_confirmation(string device_id) {
            // Accept/reject pairing
            DeviceManager.Device device = base.get_device(device_id);

            try {
                Notify.Notification notification = new Notify.Notification ("Pairing request", "Pairing request from " + device.name, "dialog-information");
                notification.add_action ("accept-pairing", "Accept", (n, a) => {
                    debug("Pairing was accepted by user");
                    device.accept_pairing();
                    try { n.close(); } catch (Error e) {}
                    notifications.unset(n.id);
                });
                notification.add_action ("reject-pairing", "Reject", (n, a) => {
                    debug("Pairing was rejected by user");
                    device.reject_pairing();
                    try { n.close(); } catch (Error e) {}
                    notifications.unset(n.id);
                });
                // Display notification and assign it an id
                notification.show ();
                // Keep the notification in memory to handle the action replies
                notifications[notification.id] = notification;
            } catch (Error e) {
                error("Error: %s", e.message);
            }
        }

        public override void report_error(string title, string description) {
            try {
                Notify.Notification notification = new Notify.Notification ("A core error was reported: " + title, description, "");
                notification.show ();
            } catch (Error e) {
                error("Error: %s", e.message);
            }
        }
    }

    public class Application {
        private static bool version;
        private static bool api_version;
        private static bool debug = false;
        private const OptionEntry[] options = {
            { "version", 0, 0, OptionArg.NONE, ref version, "Display version number", null },
            { "api-version", 0, 0, OptionArg.NONE, ref api_version, "Display API version number", null },
            { "debug", 'd', 0, OptionArg.NONE, ref debug, "Show debug information", null},
            { null }
        };

        static int main (string[] args) {
            GLib.Intl.setlocale();

            try {
                var opt_context = new OptionContext ("- gconnect");
                opt_context.set_help_enabled (true);
                opt_context.add_main_entries (options, null);
                opt_context.parse (ref args);
            } catch (OptionError e) {
                stdout.printf ("%s\n", e.message);
                stdout.printf ("Run '%s --help' to see a full list of available command line options.\n", args[0]);
                return 1;
            }

            
            if (version) {
                stdout.printf ("%s %s\n", Config.APP_NAME, Config.BUILD_VERSION);
                return 0;
            } else if (api_version) {
                stdout.printf ("%s\n", Config.PACKAGE_SUFFIX);
                return 0;
            }

            if (debug) {
                Environment.set_variable("G_MESSAGES_DEBUG", "all", false);
                message("Gconnect daemon started in debug mode.");
            }

//            Gdk.init(ref args);
            Notify.init("gconnect");

            var core = CoreDaemon.instance();
            if (core == null) {
                error("Cannot initialize core");
            }

            // GLib loop
            var loop = new MainLoop();

            loop.run();

            // Unregister DBus
            core.close();
            
            return 0;
        }
    }
}
