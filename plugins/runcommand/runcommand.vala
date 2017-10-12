using GLib;
using Peas;
using Gconnect;

namespace PluginsGconnect.RunCommand {
    
    public abstract class SimpleProxy : GLib.Object {
        protected unowned Gconnect.Plugin.PluginProxy proxy;
        protected string name;

        protected unowned DBusConnection dbus_connection;
        
        public SimpleProxy(Gconnect.Plugin.PluginProxy proxy) {
            this.proxy = proxy;
            this.name = proxy.name;
            this.proxy.received_packet.connect(receive);

            if (this.proxy.dbus_connection() != null) {
                publish();
            } else {
                // Delayed publication on DBus
                this.proxy.published.connect(publish);
            }
        }

        protected abstract void receive(Gconnect.NetworkProtocol.Packet pkt);
        protected abstract void publish();
        [DBus (visible = false)]
        public abstract void unpublish();
    }

    public class RunCommandProxy : SimpleProxy {
        protected const string PACKET_TYPE_RUNCOMMAND = "kdeconnect.runcommand";
        private const string GSETTING_ID = "org.gconnect.plugins.runcommand";
        
        private GLib.Settings settings;
        private bool threaded = false;
        
        public RunCommandProxy(Gconnect.Plugin.PluginProxy proxy) {
            base(proxy);
            if (Thread.supported ()) {
                this.threaded = true;
            }

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
            this.settings.changed["commands"].connect (() => {
                this.send_config();
            });

            this.send_config();
        }

        private void send_config() {
            // Build a object:
            Json.Builder builder = new Json.Builder ();

            builder.begin_object ();
            builder.set_member_name ("commandList");
            builder.begin_object ();

            var @var = this.settings.get_value("commands");
            string? val = null;
            string? key = null;
            VariantIter iter = @var.iterator();
            while (iter.next ("{ss}", &key, &val)) {
                if (key != null && val != null) {
                    builder.set_member_name (key);
                    builder.begin_object ();
                    builder.set_member_name ("name");
                    builder.add_string_value (key);
                    builder.set_member_name ("command");
                    builder.add_string_value (val);
                    builder.end_object ();
                }
            }
            builder.end_object ();
            builder.end_object ();

            // Generate a string:
            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);

            string commands = generator.to_data (null);
            var pkt = new Gconnect.NetworkProtocol.Packet.with_string_body(PACKET_TYPE_RUNCOMMAND, commands);
            this.proxy.request(pkt);
        }
        
        private void exec_command(string cmd) {
            string[] cmd_list = {"/bin/sh", "-c", cmd};
            string full_cmd = string.joinv(" ", cmd_list);
            if (this.threaded) {
                exec_command_thread(full_cmd);
            } else {
                exec_command_async(full_cmd);
            }
        }

        private void exec_command_async(string cmd) {
            try {
                debug("Async exec: %s", cmd);
                Process.spawn_command_line_async(cmd);
            } catch (SpawnError e) {
                debug("Error executing command '%s' ->\n%s", cmd, e.message);
            }
        }

        private void exec_command_thread(string cmd) {
            try {
                new Thread<int>.try("cmd", () => {
                    string cmd_stdout;
                    string cmd_stderr;
                    int cmd_status;
                    try {
                        debug("Thread exec: %s", cmd);
                        Process.spawn_command_line_sync (cmd,
                                                out cmd_stdout,
                                                out cmd_stderr,
                                                out cmd_status);
                    } catch (SpawnError e) {
                        debug("Error executing command '%s' ->\n%s", cmd, e.message);
                    }
                    if (cmd_stderr != null && cmd_stderr != "") {
                        this.proxy.log("stderr:\n%s".printf(cmd_stderr));
                    }
                    return cmd_status;
                });
            } catch (Error e) {
                debug("Error creating a new thread: %s", e.message);
            }
        }

        protected override void receive(Gconnect.NetworkProtocol.Packet pkt) {
            if (pkt.has_field("requestCommandList") ? pkt.get_bool("requestCommandList") : false) {
                send_config();
            }

            if (pkt.has_field("key")) {
                string key = pkt.get_string("key");
                var @var = this.settings.get_value("commands");
                var cmd_var = @var.lookup_value(key, VariantType.STRING) ;
                if (cmd_var != null) {
                    string cmd = cmd_var.get_string();
                    exec_command(cmd);
                }
            }
        }

        protected override void publish() {}

        [DBus (visible = false)]
        public override void unpublish() {}
    }

    public class RunCommand : GLib.Object, Gconnect.Plugin.Plugin {
        public unowned Gconnect.DeviceManager.Device device { get; construct set; }
        private RunCommandProxy worker = null;

        /* The "constructor" with the plugin name as argument */
        public void activate(string name) {
            this.worker = new RunCommandProxy(this.device.get_plugin(name));
        }
        
        public void deactivate() {
            if (this.worker != null) {
                this.worker.unpublish();
                this.worker = null;
            }
        }
    }
}

// Register extension types
[ModuleInit]
public void peas_register_types (TypeModule module) {
        var objmodule = module as Peas.ObjectModule;

        objmodule.register_extension_type(typeof (Gconnect.Plugin.Plugin), typeof (PluginsGconnect.RunCommand.RunCommand));
}
