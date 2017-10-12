using GLib;
using Peas;
using Gconnect;

namespace PluginsGconnect.MprisControl {
    
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

    string? parse_dbus_name(string dbus_name) {
        var re = /org.mpris.MediaPlayer2.(?P<name>.+)$/;
        MatchInfo match_info;
        re.match(dbus_name, 0, out match_info);
        if (match_info.get_match_count() > 0) {
            var name = match_info.fetch_named("name");
            return name;
        }
        return null;
    }
    
    bool parse_metadata(Gconnect.NetworkProtocol.Packet pkt, HashTable<string,Variant> metadata) {
        bool ret = false;
        if (metadata.contains("xesam:title")) {
            var now_playing = metadata.@get("xesam:title").get_string();
            if (metadata.contains("xesam:artist")) {
                now_playing = metadata.@get("xesam:artist").get_child_value(0).get_string() + " - " + now_playing;
            }
            pkt.set_string("nowPlaying", now_playing);
            ret = true;
        }
        if (metadata.contains("mpris:length")) {
            var len = metadata.@get("mpris:length").get_int64();
            pkt.set_int("length", (int)(len/1000));
            ret = true;
        }
        return ret;
    }

    [DBus(name = "org.gconnect.plugins.mpriscontrol")]
    public class MprisControlProxy : SimpleProxy {
        protected const string PACKET_TYPE_MPRIS = "kdeconnect.mpris";
        private const string MPRIS_IFACE = "org.mpris.MediaPlayer2.Player";

        private Gee.HashMap<string, MprisClient?> player_list;
        private string[] action_list = {"CanPause", "CanPlay", "CanGoNext", "CanGoPrevious", "CanSeek"};
        
        private DBusIface dbus_obj;
        private ulong dbus_obj_signal;
        
        public MprisControlProxy(Gconnect.Plugin.PluginProxy proxy) {
            base(proxy);
            this.player_list = new Gee.HashMap<string, MprisClient?>();
            
            watch_dbus();
        }
        
        private void watch_dbus() {
            try {
                this.dbus_obj = Bus.get_proxy_sync(BusType.SESSION,
                                                   "org.freedesktop.DBus",
                                                   "/org/freedesktop/DBus",
                                                   DBusProxyFlags.DO_NOT_LOAD_PROPERTIES);
            } catch (IOError e) {
                debug("Cannot connect to DBus: %s", e.message);
                return;
            }

            this.dbus_obj_signal = this.dbus_obj.name_owner_changed.connect(on_name_owner_changed);
            this.dbus_obj.list_names.begin((obj, res) => {
                try {
                    var services = this.dbus_obj.list_names.end(res);
                    foreach (var service in services) {
                        on_name_owner_changed(service, "", "new");
                    }
                } catch (DBusError e) {
                    debug("Cannot list dbus names: %s", e.message);
                }
            });
        }

        private void on_name_owner_changed(string dbus_name, string old, string @new) {
            var name = parse_dbus_name(dbus_name);
            if (name != null) {
                if ( old == "" && @new != "" && !this.player_list.has_key(name)) {
                    debug("MPRIS service %s just came online", name);
                    add_player(name);
                } else if ( old != "" && @new == "" && this.player_list.has_key(name)) {
                    debug("MPRIS service %s just went offline", name);
                    remove_player(name);
                }
            }
        }
        
        private void add_player(string name) {
            MprisClient p = null;
            this.player_list[name] = null; // block further call
            new_iface.begin("org.mpris.MediaPlayer2." + name, (obj, res) => {
                p = new_iface.end(res);
                if (p == null) {
                    debug("Could not instanciate client");
                    return;
                }
                p.add_player_signal(p.player.seeked.connect(on_seeked));
                p.add_player_signal(p.player.notify.connect((s,p) => {
                    debug("property '%s' has changed!\n", p.name);
                }));
                p.add_prop_signal(p.prop.properties_changed.connect(on_properties_changed));
                this.player_list[name] = (owned)p;
                send_player_list();
            });
        }
        
        private void remove_player(string name) {
            var p = this.player_list[name];
            p.disconnect_signals();
            this.player_list.unset(name);
            send_player_list();
        }

        private void send_player_list() {
            var pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_MPRIS);
            var arr = this.player_list.keys.to_array();
            pkt.set_strv("playerList", arr);
            this.proxy.request(pkt);
        }

        [Callback]
        private void on_seeked(PlayerIface sender, int64 position) {
            var name = parse_dbus_name(sender.get_name());
            if (name != null && name in this.player_list.keys) {
                var pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_MPRIS);
                pkt.set_string("player", name);
                pkt.set_int("pos", (int)(position/1000));
                this.proxy.request(pkt);
            }
        }

        [Callback]
        private void on_properties_changed(DbusPropIface sender, string iface, HashTable<string,Variant> changed, string[] invalid) {
            var name = parse_dbus_name(sender.get_name());
            if (name == null || !(name in this.player_list.keys)) {
                return;
            }
            var p = this.player_list[name];
            
            var pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_MPRIS);
            bool send = false;
            if (changed.contains("Volume")) {
                var volume = (int)(changed.@get("Volume").get_double()*100);
                if (volume != p.previous_volume) {
                    p.previous_volume = volume;
                    pkt.set_int("volume", volume);
                    send = true;
                }
            }
            if (changed.contains("Metadata")) {
                var metadata_var = changed.@get("Metadata");
                HashTable<string,Variant> metadata = new HashTable<string,Variant>(GLib.str_hash, GLib.str_equal);
                for (size_t i = 0; i < metadata_var.n_children(); i++) {
                    string key;
                    Variant val;
                    metadata_var.get_child(i, "{sv}", out key, out val);
                    metadata.insert(key, val);
                }
                send = send || parse_metadata(pkt, metadata);
            }
            if (changed.contains("PlaybackStatus")) {
                var status = changed.@get("PlaybackStatus").get_string();
                bool is_playing = (status == "Playing");
                pkt.set_bool("isPlaying", is_playing);
                send = true;
            }
            foreach (var prop in this.action_list) {
                if (changed.contains(prop)) {
                    var camel = prop.down(1) + prop.substring(1);
                    bool res = changed.@get(prop).get_boolean();
                    pkt.set_bool(camel, res);
                    send = true;
                }
            }
            // For players that do not implement the Seeked signal
            if (changed.contains("Position")) {
                var pos = (int)(changed.@get("Position").get_int32());
                pkt.set_int("pos", pos);
                send = true;
            }
            
            if (send) {
                pkt.set_string("player", name);
                bool can_seek = p.player.can_seek;
                if (can_seek) {
                    var pos = p.prop.get_sync(MPRIS_IFACE, "Position").get_int64();
                    pkt.set_int("pos", (int)(pos/1000));
                }
                this.proxy.request(pkt);
            }
        }

        protected override void receive(Gconnect.NetworkProtocol.Packet pkt) {
            if (pkt.has_field("playerList")) {
                // Whoever sent this is an mpris client and not an mpris control!
                return;
            }

            // Send the player list
            string? player_name = pkt.has_field("player") ? pkt.get_string("player") : null;
            
            bool valid_player = player_name != null && player_name in this.player_list.keys;
            if (!valid_player || pkt.has_field("requestPlayerList")) {
                send_player_list();
                if (!valid_player) {
                    return;
                }
            }
            var p = this.player_list[player_name];

            if (pkt.has_field("action")) {
                var action = pkt.get_string("action");
                try {
                    p.player.call.begin(action, null, 0, 500);
                } catch (Error e) {
                    debug("Error calling dbus method %s: %s", action, e.message);
                }
            }
            if (pkt.has_field("setVolume")) {
                var volume = pkt.get_double("setVolume")/100;
                p.player.volume = volume;
            }
            if (pkt.has_field("Seek")) {
                var offset = (int64)(pkt.get_int("Seek"));
                try {
                    p.player.seek(offset);
                } catch (Error e) {
                    debug("Error calling dbus method Seek: %s", e.message);
                }
            }
            if (pkt.has_field("SetPosition")) {
                var position = pkt.get_int("SetPosition")*1000;
                var last_pos = (int)(p.prop.get_sync(MPRIS_IFACE, "Position").get_int64());
                // TODO: not working, it seems a problem with int types. Always gives last_pos = 0
//                var last_pos = (int)p.player.position;
                var offset = position - last_pos;
//                debug("SetPosition to %d, current %d -> offset %d", position, last_pos, offset);
                try {
                    p.player.seek(offset);
                } catch (Error e) {
                    debug("Error calling dbus method Seek: %s", e.message);
                }
            }
            
            bool send = false;
            var new_pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_MPRIS);
            if (pkt.has_field("requestNowPlaying")) {
                var metadata = p.player.metadata;  // working
                parse_metadata(new_pkt, metadata);
                var position = p.prop.get_sync(MPRIS_IFACE, "Position").get_int64();
                new_pkt.set_int("pos", (int)(position/1000));
                var status = p.player.playback_status;
                new_pkt.set_bool("isPlaying", (status == "Playing"));
                new_pkt.set_bool("canPause", p.player.can_pause);
                new_pkt.set_bool("canPlay", p.player.can_play);
                new_pkt.set_bool("canGoNext", p.player.can_go_next);
                new_pkt.set_bool("canGoPrevious", p.player.can_go_previous);
                new_pkt.set_bool("canSeek", p.player.can_seek);
                send = true;
            }
            if (pkt.has_field("requestVolume")) {
                var volume = p.player.volume;
                new_pkt.set_int("volume", (int)volume * 100);
                send = true;
            }
            if (send) {
                new_pkt.set_string("player", player_name);
                this.proxy.request(new_pkt);
            }
        }

        protected override void publish() {}

        [DBus (visible = false)]
        public override void unpublish() {
            foreach (var p in this.player_list.values) {
                p.disconnect_signals();
            }
            this.dbus_obj.disconnect(this.dbus_obj_signal);
        }
    }

    public class MprisControl : GLib.Object, Gconnect.Plugin.Plugin {
        public unowned Gconnect.DeviceManager.Device device { get; construct set; }
        private MprisControlProxy worker = null;

        /* The "constructor" with the plugin name as argument */
        public void activate(string name) {
            this.worker = new MprisControlProxy(this.device.get_plugin(name));
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

        objmodule.register_extension_type(typeof (Gconnect.Plugin.Plugin), typeof (PluginsGconnect.MprisControl.MprisControl));
}
