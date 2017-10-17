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

namespace Gconnect.LanConnection {

//    public class LanDeviceLinkInfo : Connection.DeviceLinkInfo {
//        public string peer_cert;
//        public string host_address;
        
//        public LanDeviceLinkInfo (string cert, string host) {
//            this.peer_cert = cert;
//            this.host_address = host;
//        }
//    }


    public class LanDeviceLink : Connection.DeviceLink {
        private LanSocketConnection socket_connection;
        
        public override string name { get; protected set; default="LanLink";}

        public LanDeviceLink(string device_id, Connection.LinkProvider parent, LanSocketConnection conn) {
            base(device_id, parent);
            reset(conn);
        }
            
        public override void parse_device_info(ref DeviceManager.DeviceInfo dev) {
            dev.ip_address = socket_connection.host_address.address.to_string();
            dev.encryption = socket_connection.peer_cert;
        }
        
        public override bool link_should_be_kept_alive() { return true;}

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
        
        public void reset(LanSocketConnection conn) {
            info("Reset the Lan device link");
            this.clean();
            
            this.socket_connection = conn;

            this.socket_connection.forced_close.connect(close);
            this.socket_connection.packet_received.connect(packet_received);

            bool has_cert = Config.Config.instance().has_certificate(device_id);
            set_and_announce_pair_status(has_cert? Connection.DeviceLink.PairStatus.PAIRED : Connection.DeviceLink.PairStatus.NOT_PAIRED);

            // Watch for incoming messages
            this.socket_connection.monitor();
        }
        
        public override void set_pair_status(Connection.DeviceLink.PairStatus status) {
            var peer_cert = this.socket_connection.peer_cert;
            if (status == Connection.DeviceLink.PairStatus.PAIRED && peer_cert == null) {
                pairing_error("This device cannot be set to paired because it is running an old version of KDE Connect.");
                return;
            }
            set_and_announce_pair_status(status);
            if (status == Connection.DeviceLink.PairStatus.PAIRED) {
                assert(Config.Config.instance().is_paired(device_id));
                // Store certificate
                assert(peer_cert != null);
                assert(Config.Config.instance().set_certificate_for_device(device_id, peer_cert));
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
        
        public override void user_requests_pair() {
            if (this.socket_connection.peer_cert == null) {
                pairing_error("This device cannot be asked to pair because it is running an old version of KDE Connect.");
            } else {
                request_pair();
            }
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
