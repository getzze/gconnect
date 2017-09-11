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

    public class LanDeviceLink : Connection.DeviceLink {
        private SocketConnection conn;
        private DataOutputStream dos;
        private DataInputStream dis;
        private uint source_id = 0;
        private ConnectionStarted connection_source;
//        private QHostAddress mHostAddress;

        private ArrayList<LanConnection.LanPairingHandler> pairing_handlers;
        
        public override string name { get; protected set; default="LanLink";}

        public LanDeviceLink(string device_id, Connection.LinkProvider parent, SocketConnection sc, ConnectionStarted origin) {
            base(device_id, parent);
            reset(sc, origin);
        }
            
        private void clean () {
            if (source_id > 0) {
                Source.remove(source_id);
                source_id = 0;
            }
            if (this.conn != null) {
                try {
                    if (!this.dos.is_closed()) { this.dos.close();}
                } catch (IOError e) {
                    warning("Error closing output stream: %s\n", e.message);
                } finally {
                    dos = null;
                }
                try {
                    if (!this.dis.is_closed()) { this.dis.close();}
                } catch (IOError e) {
                    warning("Error closing input stream: %s\n", e.message);
                } finally {
                    dis = null;
                }

                try {
                    if (!this.conn.is_closed()) { this.conn.close();}
                } catch (IOError e) {
                    warning("Error closing connection: %s\n", e.message);
                }
            }
        }
        
        private void close() {
            this.clean();
            this.destroyed(device_id);
        }

        public void reset(SocketConnection sc, ConnectionStarted origin) {
            this.clean();
            
            this.connection_source = origin;

            //We take ownership of the socket.
            //When the link provider destroys us,
            //the socket (and the reader) will be
            //destroyed as well
            this.conn = sc;
            var addr = (InetSocketAddress)this.conn.get_remote_address();
            try {
                this.conn.connect(addr);
            } catch (IOError e) {
                error("Error reconnecting to %s: %s", addr.address.to_string(), e.message);
            }
            this.dos = new DataOutputStream (this.conn.output_stream);
            this.dis = new DataInputStream (this.conn.input_stream);
            // messages end with \n\n
//            this.dis.set_newline_type(DataStreamNewlineType.LF);
            // Watch for incoming messages
            SocketSource source = this.conn.socket.create_source(IOCondition.IN);
            source.set_callback( (src, cond) => {
                if (!(IOCondition.HUP in cond)) {
                    this.data_received();
                }
                return GLib.Source.CONTINUE; // continue watching
            });
            source_id = source.attach(MainContext.default ());
            
//            QString certString = KdeConnectConfig::instance()->getDeviceProperty(deviceId(), QStringLiteral("certificate"));
            string? cert = null;
//            set_and_announce_pair_status(cert==null? Connection.DeviceLink.PairStatus.NOT_PAIRED : Connection.DeviceLink.PairStatus.PAIRED);
            // If already paired
            bool is_paired = Config.Config.instance().is_paired(device_id);
            set_and_announce_pair_status(is_paired? Connection.DeviceLink.PairStatus.PAIRED : Connection.DeviceLink.PairStatus.NOT_PAIRED);
        }
        
        public override void set_pair_status(Connection.DeviceLink.PairStatus status) {
//            if (status == PairStatus.PAIRED && mSocketLineReader->peerCertificate().isNull()) {
            if (false) {
                pairing_error("This device cannot be paired because it is running an old version of KDE Connect.");
                return;
            }

            set_and_announce_pair_status(status);
            if (status == Connection.DeviceLink.PairStatus.PAIRED) {
                assert(Config.Config.instance().is_paired(device_id));
//                Q_ASSERT(!mSocketLineReader->peerCertificate().isNull());
//                KdeConnectConfig::instance()->setDeviceProperty(deviceId(), QStringLiteral("certificate"), mSocketLineReader->peerCertificate().toPem());
            }
        }

        private async void send_packet_async(NetworkProtocol.Packet input) {
            try {
                string sent = input.serialize() + "\n";
//                res = dos.put_string(sent);
                size_t len;
                yield dos.write_all_async(sent.data, Priority.DEFAULT_IDLE, null, out len);
                debug("Packet sent: %s", sent);
            } catch (IOError e) {
                error("Error sending packet: %s\n", e.message);
            }
        }
        
        public override bool send_packet(NetworkProtocol.Packet input) {
            if (input.has_payload()) {
//                np.setPayloadTransferInfo(sendPayload(np)->transferInfo());
            }

            send_packet_async(input);

            //Actually we can't detect if a package is received or not. We keep TCP
            //"ESTABLISHED" connections that look legit (return true when we use them),
            //but that are actually broken (until keepalive detects that they are down).
            bool res = true;
            return res;
        }
        
//        public UploadJob send_payload(NetworkProtocol.Packet input) {
//            UploadJob job = new UploadJob(input.payload, device_id);
//            job.start();
//            return job;
//        }

        public override void user_requests_pair() {
//            if (mSocketLineReader->peerCertificate().isNull()) {
            if (false) {
                pairing_error("This device cannot be paired because it is running an old version of KDE Connect.");
            } else {
                ((LanLinkProvider)this.provider).user_requests_pair(device_id);
            }
        }
        
        public override void user_requests_unpair() {
            ((LanLinkProvider)this.provider).user_requests_unpair(device_id);
        }

        public override bool link_should_be_kept_alive() { return true;}

        private async void data_received() {
            string data = null;
            try {
//                debug("Wait for something");
                data = yield dis.read_line_utf8_async(Priority.HIGH_IDLE);
            } catch (IOError e) {
                warning("Error receiving packet: %s", e.message);
                if ("Stream has outstanding operation" in e.message) {
                    dis.clear_pending();
                    warning("Trying to clear pending operations.");
                }
            }
            if (data == null) {
                return;
            }
            debug("Received: %s", data);
            var raw_pkt = NetworkProtocol.Packet.unserialize(data);

            if (raw_pkt.packet_type == NetworkProtocol.PACKET_TYPE_PAIR) {
                //TODO: Handle pair/unpair requests and forward them (to the pairing handler?)
                ((LanLinkProvider)this.provider).incoming_pair_packet(this, raw_pkt);
                return;
            }
                
            NetworkProtocol.Packet pkt = null;
            if (raw_pkt.packet_type == NetworkProtocol.PACKET_TYPE_ENCRYPTED) {
                try {
                    pkt = raw_pkt.decrypt();
                } catch (NetworkProtocol.PacketError e) {
                    debug("Error with encrypted pakcet: %s", e.message);
                    pkt = raw_pkt;
                }
            }

            debug("LanDeviceLink data received: %s", pkt.to_string());

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
