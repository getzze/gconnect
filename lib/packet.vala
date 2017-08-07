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

namespace NetworkProtocol {
    const string PACKAGE_TYPE_IDENTITY = "kdeconnect.identity";
    const string PACKAGE_TYPE_PAIR = "kdeconnect.pair";
    const int PROTOCOL_VERSION = 7;

    public class Packet: GLib.Object {

        public unowned int64 id { get; private set; }
        public unowned string type { get; private set; }
        public unowned Json.Object body { get; private set; }
        public unowned Json.Object payload_transfer_info { get; private set; }
        public unowned uint64 payload_size { get; private set; }

        public Packet (const string type, const Json.Object body = {}, const string id = 0) {
            if (id==0) {
                this.id = get_real_time() / 1000;
            } else {
                this.id = id;
            }
            this.type = type;
            this.body = body;

            this.payload_size = 0;
            this.payload_transfer_info = {};
//             this.payload = {};
        }

        public static Packet new_identity_packet() {
            var config = Config.Config.instance();
            var np = new Packet(PACKAGE_TYPE_IDENTITY);
            np.set<string>("deviceId", config->deviceId());
            np.set<string>("deviceName", config->name());
            np.set<string>("deviceType", config->deviceType());
            np.set<int>("protocolVersion",  PROTOCOL_VERSION);
            np.set<string[]>("incomingCapabilities", PluginLoader::instance()->incomingCapabilities());
            np.set<string[]>("outgoingCapabilities", PluginLoader::instance()->outgoingCapabilities());

            return np;
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
                    if (root_obj.has_member(m) == false)
                        throw new PacketError.MALFORMED(@"Missing $m member");
                }

                string type = root_obj.get_string_member("type");
                int64 id = root_obj.get_int_member("id");
                Json.Object body = root_obj.get_object_member("body");

                vdebug("packet type: %s", type);

                return new Packet(type, body, id);
            } catch (Error e) {
                message("failed to parse message: \'%s\', error: %s",
                        data, e.message);
            }
            return null;
        }

        public string serialize() {
            var gen = new Json.Generator();
            // root node
            var root = new Json.Node(Json.NodeType.OBJECT);
            var root_obj = new Json.Object();
            root_obj.set_string_member("type", pkt_type);
            root_obj.set_int_member("id", id);
            root_obj.set_object_member("body", body);
            root.set_object(root_obj);

            gen.set_root(root);
            gen.set_pretty(false);

            string data = gen.to_data(null);
            return data;
        }

        public bool has(string field) {
            return this.body.has_member(field);
        }

        public T get<T>(string field, const T default = (T){}) {
            if (this.has<T>(field)) {
                unowned Json.Node node = this.body.get_member(field);
                if (T is node.get_value_type()) {
                    return (T)node.get_value();
                }
            }
            return (T)default;
        }

        public void set<T>(string field, T @value) {
            unowned Json.Node node = new Json.Node();
            node.set_value(@value);
            this.body.set_member(field, (owned) node);
        }
    };
        
    
}
