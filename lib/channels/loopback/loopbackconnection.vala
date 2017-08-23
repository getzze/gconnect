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

namespace Gconnect.LoopbackConnection {

    public class LoopbackLinkProvider : Connection.LinkProvider {
        private LoopbackDeviceLink? _device_link = null;
        private NetworkProtocol.Packet identity_packet;

        public LoopbackLinkProvider() {
            this.identity_packet = new NetworkProtocol.Packet.identity();
        }
        
        public override string name { get; protected set; default="LoopbackLinkProvider"; }
        public override int priority { get; protected set; default=PRIORITY_LOW; }
        
        public override void on_start() { on_network_change(); }

        public override void on_stop() {
            if (_device_link!=null) {
                _device_link = null;
            }
        }

        public override void on_network_change() {
            LoopbackDeviceLink new_device_link = new LoopbackDeviceLink("loopback", this);

            // Send received connection for the local device
            debug("Send self identity package: %s", this.identity_packet.to_string());
            on_connection_received(this.identity_packet, new_device_link);

            if (_device_link!=null) {
                _device_link = null;
            }
            _device_link = new_device_link;
        }

    }
    
    public class LoopbackDeviceLink : Connection.DeviceLink {

        public LoopbackDeviceLink(string device_id, LoopbackLinkProvider parent) {
            base(device_id, parent);
        }

        public override string name { get; protected set; default="LoopbackDeviceLink";}

        public override bool send_packet(NetworkProtocol.Packet input) {
            var output = NetworkProtocol.Packet.unserialize(input.serialize());

//             //LoopbackDeviceLink does not need deviceTransferInfo
//             if (input.hasPayload()) {
//                 bool b = input.payload()->open(QIODevice::ReadOnly);
//                 Q_ASSERT(b);
//                 output.setPayload(input.payload(), input.payloadSize());
//             }

            received_packet(output);
            return true;

        }

        //user actions
        public override void user_requests_pair() { pair_status = PairStatus.PAIRED; }
        public override void user_requests_unpair() { pair_status = PairStatus.NOT_PAIRED; }
        
    }
} 
