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

namespace Gconnect.BluetoothConnection {

    public class BluetoothDeviceLink : Connection.DeviceLink {
        private BluetoothSocketConnection socket_connection;
        private uint source_id = 0;
        public string bt_address { get; private set; }

        public override string name { get; protected set; default="BluetoothLink";}

        public BluetoothDeviceLink(string device_id, Connection.LinkProvider parent, BluetoothSocketConnection conn) {
            base(device_id, parent);
            reset(conn);
        }
            
        public override bool link_should_be_kept_alive() {
//            return (this._pair_status == Connection.DeviceLink.PairStatus.PAIRED);
            return true;
        }

        private void close() {
            info("Close the %s", name);
            clean();
            destroyed(device_id);
        }
        
        private void clean() {
            if (this.socket_connection != null) {
                this.socket_connection.clean();
            }
        }
        
        public void reset(BluetoothSocketConnection conn) {
            info("Reset the Bluetooth device link");
            this.clean();
            
            this.bt_address = conn.address;
            this.socket_connection = conn;

            this.socket_connection.forced_close.connect(close);
            this.socket_connection.packet_received.connect(packet_received);

            bool is_paired = Config.Config.instance().is_paired(device_id);
            set_and_announce_pair_status(is_paired? Connection.DeviceLink.PairStatus.PAIRED : Connection.DeviceLink.PairStatus.NOT_PAIRED);

            // Watch for incoming messages
            this.socket_connection.monitor();
        }
        
        public override void set_pair_status(Connection.DeviceLink.PairStatus status) {
            set_and_announce_pair_status(status);
            if (status == Connection.DeviceLink.PairStatus.PAIRED) {
                assert(Config.Config.instance().is_paired(device_id));
            }
        }

//        public UploadJob send_payload(NetworkProtocol.Packet input) {
//            UploadJob job = new UploadJob(input.payload, device_id);
//            job.start();
//            return job;
//        }

        public override bool send_packet(NetworkProtocol.Packet input) {
            if (input.has_payload()) {
//                np.setPayloadTransferInfo(sendPayload(np)->transferInfo());
            }
            return this.socket_connection.send_packet(input);
        }
        
        private void packet_received(NetworkProtocol.Packet pkt) {
            if (pkt.packet_type == NetworkProtocol.PACKET_TYPE_PAIR) {
                this.incoming_pair_packet(pkt);
                return;
            }
                
            if (pkt.packet_type == NetworkProtocol.PACKET_TYPE_ENCRYPTED) {
                warning("This is an old protocol, it is not supported anymore, use TLS.");
                return;
            }


//            if (package.hasPayloadTransferInfo()) {
//                //qCDebug(KDECONNECT_CORE) << "HasPayloadTransferInfo";
//                QVariantMap transferInfo = package.payloadTransferInfo();
//                //FIXME: The next two lines shouldn't be needed! Why are they here?
//                transferInfo.insert(QStringLiteral("useSsl"), true);
//                transferInfo.insert(QStringLiteral("deviceId"), deviceId());
//                DownloadJob* job = new DownloadJob(mSocketLineReader->peerAddress(), transferInfo);
//                job->start();
//                package.setPayload(job->getPayload(), package.payloadSize());
//            }

            received_packet(pkt);
        }
    }
} 
