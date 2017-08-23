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

using Json;
// using Connection;
// using DeviceManager;
// using Config;

namespace Gconnect.NetworkProtocol {
    const string PACKET_TYPE_IDENTITY = "kdeconnect.identity";
    const string PACKET_TYPE_PAIR = "kdeconnect.pair";
    const string PACKET_TYPE_ENCRYPTED = "kdeconnect.encrypted";
    const int PROTOCOL_VERSION = 7;

    public errordomain PacketError {
        MALFORMED
    }

    public class Packet: GLib.Object {
        
        public int64 id { get; private set; }
        public string packet_type { get; private set; }
        private Json.Object body { get; private set; }
        public uint64 payload_size { get; private set; }
        private Json.Object payload_transfer_info { get; set; }

        public Packet (string type, int64 id = 0 ) {
            if (id==0) {
                id = get_real_time() / 1000;
            }
            this.id = id;
            this.packet_type = type;
            this.body = new Json.Object();
            
            this.payload_size = 0;
            this.payload_transfer_info = new Json.Object();
//             this.payload = {};
        }

        internal Packet.with_body (string type, owned Json.Object body, int64 id = 0) {
            this(type, id);
            this.body = (owned)body;
        }

        public Packet.identity() {
            var config = Config.Config.instance();
            this(PACKET_TYPE_IDENTITY);
            bool dbg = true;
            if (!dbg) {
                this.set_string("deviceId",   config.device_id);
                this.set_string("deviceName", config.device_name);
                this.set_string("deviceType", config.device_category);
                this.set_int("protocolVersion",  PROTOCOL_VERSION);
                var pm = Plugin.PluginManager.instance();
                this.set_strv("incomingCapabilities", pm.incoming_capabilities);
                this.set_strv("outgoingCapabilities", pm.outgoing_capabilities);
            } else {
                this.set_string("deviceId", "testId");
                this.set_string("deviceName", "testName");
                this.set_string("deviceType", "testType");
                this.set_int("protocolVersion",  PROTOCOL_VERSION);
                this.set_strv("incomingCapabilities", {});
                this.set_strv("outgoingCapabilities", {});
            }
        }

        public static Packet? unserialize(string data) {
            Json.Parser jp = new Json.Parser();

            try {
                jp.load_from_data(data, -1);
                // there should be an object at root node
                Json.Object root_obj = jp.get_root().get_object();
                if (root_obj == null)
                    throw new PacketError.MALFORMED("Missing root object");

                // object needs to have these fields
                string[] required_members = {"type", "id", "body"};
                foreach (string m in required_members) {
                    if (root_obj.has_member(m) == false) {
                        throw new PacketError.MALFORMED(@"Missing $m member");
                    }
                }

                string type = root_obj.get_string_member("type");
                int64 id = root_obj.get_int_member("id");
                Json.Object body = root_obj.get_object_member("body");

                debug("Packet type: %s", type);

                return new Packet.with_body(type, body, id);
            } catch (Error e) {
                message("Failed to parse message: \'%s\', error: %s",
                        data, e.message);
            }
            return null;
        }
        
        public string serialize() {
            var gen = new Json.Generator();
            // root node
            var root = new Json.Node(Json.NodeType.OBJECT);
            var root_obj = new Json.Object();
            root_obj.set_string_member("type", this.packet_type);
            root_obj.set_int_member("id", this.id);
            root_obj.set_object_member("body", this.body);
            root.set_object(root_obj);

            gen.set_root(root);
            gen.set_pretty(false);

            string data = gen.to_data(null);
            // Reown body Object
            this.body = root_obj.get_object_member("body");
            return data;
        }

        public string to_string() {
            return this.serialize();
        }

        public bool has_field(string field) {
            return this.body.has_member(field);
        }

        public void remove_field(string field) {
            this.body.remove_member(field);
        }

        public bool get_bool(string field) {
            if (!this.has_field(field)) {
                message("Member %s dos not exist", field);
            }
            return this.body.get_boolean_member(field);
        }

        public int get_int(string field) {
            if (!this.has_field(field)) {
                message("Member %s dos not exist", field);
            }
            return (int)this.body.get_int_member(field);
        }

        public double get_double(string field) {
            if (!this.has_field(field)) {
                message("Member %s dos not exist", field);
            }
            return this.body.get_double_member(field);
        }

        public string get_string(string field) {
            if (!this.has_field(field)) {
                message("Member %s dos not exist", field);
            }
            return this.body.get_string_member(field);
        }

        public string[] get_strv(string field) {
            if (!this.has_field(field)) {
                message("Member %s dos not exist", field);
            }
            GLib.List<Json.Node> lst = this.body.get_array_member(field).get_elements();
            string[] ret = {};
            string s;
            foreach (var n in lst) {
                s = n.get_string();
                ret += s;
            }
            return ret;
        }

        private unowned Json.Object? get_object(string field) {
            return this.body.get_object_member(field);
        }

        private unowned Json.Array? get_array(string field) {
            return this.body.get_array_member(field);
        }

        public void set_bool(string field, bool @value) {
             this.body.set_boolean_member(field, @value);
        }

        public void set_int(string field, int64 @value) {
             this.body.set_int_member(field, @value);
        }

        public void set_double(string field, double @value) {
             this.body.set_double_member(field, @value);
        }

        public void set_string(string field, string @value) {
            this.body.set_string_member(field, @value);
        }

        public void set_strv(string field, string[] @value) {
            var arr = new Json.Array();
            foreach (var s in @value) {
                arr.add_string_element(s);
            }
            this.body.set_array_member(field, (owned)arr);
        }

        private void set_object(string field, owned Json.Object @value) {
            this.body.set_object_member(field, @value);
        }

        private void set_array(string field, owned Json.Array @value) {
            this.body.set_array_member(field, @value);
        }
    }
}
