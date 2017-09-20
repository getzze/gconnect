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
        private weak Socket socket;
//        private SocketConnection conn;
        private TlsConnection tls_conn;
        private IOStream stream;
        private OutputStream dos;
        private InputStream dis;
        private uint source_id = 0;
        private ConnectionStarted connection_source;
        private InetSocketAddress host_address;
        public bool TLS { get; set; default = false; }
        public string peer_cert;

        public override string name { get; protected set; default="LanLink";}

        public LanDeviceLink(string device_id, Connection.LinkProvider parent, Socket sock, 
                                IOStream stream, ConnectionStarted origin) {
            base(device_id, parent);
            cancel_link.cancelled.connect((s)=> {
                if (source_id > 0) {
                    Source.remove(source_id);
                    source_id = 0;
                }
            });
            reset(sock, stream, origin);
        }
            
        public override bool link_should_be_kept_alive() { return true;}

        private void clean () {
            cancel_link.cancel();
            if (this.stream != null) {
                try {
                    if (!this.stream.is_closed()) { this.stream.close();}
                } catch (IOError e) {
                    warning("Error closing connection: %s\n", e.message);
                }
            }
        }
        
        private void close() {
            this.clean();
            this.destroyed(device_id);
        }

        public void reset(Socket sock, IOStream stream, ConnectionStarted origin) {
            this.clean();
            
            this.connection_source = origin;

            //We take ownership of the socket.
            //When the link provider destroys us,
            //the socket (and the reader) will be
            //destroyed as well
            this.socket = sock;
            this.socket.set_blocking(true);
            this.stream = stream;
            
            this.tls_conn = stream as TlsConnection;
            if (this.tls_conn != null && this.tls_conn is TlsConnection) {
                TLS = true;
            } else {
                TLS = false;
            }

            host_address = (InetSocketAddress)this.socket.get_remote_address();
//            try {
//                this.conn.connect(host_address);
//            } catch (IOError e) {
//                warning("Error reconnecting to %s: %s", host_address.address.to_string(), e.message);
//                this.close();
//            }
            
            this.dos = this.stream.output_stream;
            this.dis = this.stream.input_stream;
            // messages end with \n\n
//            this.dis.set_newline_type(DataStreamNewlineType.LF);
            
            if (TLS) {
//                debug("DeviceLink is a TlsConnection");
                this.peer_cert = tls_conn.get_peer_certificate().certificate_pem;
//                try {
//                    tls_conn.handshake();
//                } catch (Error e) {
//                    warning("Could not realize handshake with %s: %s", device_id, e.message);
//                }
                
                // If already paired
                bool has_cert = Config.Config.instance().has_certificate(device_id);
                set_and_announce_pair_status(has_cert? Connection.DeviceLink.PairStatus.PAIRED : Connection.DeviceLink.PairStatus.NOT_PAIRED);
            } else {
//                debug("DeviceLink is a TcpConnection");
                bool is_paired = Config.Config.instance().is_paired(device_id);
                set_and_announce_pair_status(is_paired? Connection.DeviceLink.PairStatus.PAIRED : Connection.DeviceLink.PairStatus.NOT_PAIRED);
            }
            // Watch for incoming messages
            this.monitor();
        }
        
        public override void set_pair_status(Connection.DeviceLink.PairStatus status) {
            if (TLS) {
//                var peer_cert = tls_conn.get_peer_certificate().certificate_pem;
                var peer_cert = this.peer_cert;
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
            } else {
                set_and_announce_pair_status(status);
                if (status == Connection.DeviceLink.PairStatus.PAIRED) {
                    assert(Config.Config.instance().is_paired(device_id));
                }
            }
        }

//        public UploadJob send_payload(NetworkProtocol.Packet input) {
//            UploadJob job = new UploadJob(input.payload, device_id);
//            job.start();
//            return job;
//        }

        public override void user_requests_pair() {
//            if (TLS && tls_conn.get_peer_certificate() == null) {
            if (TLS && this.peer_cert == null) {
                pairing_error("This device cannot be asked to pair because it is running an old version of KDE Connect.");
            } else {
//                ((LanLinkProvider)this.provider).user_requests_pair(device_id);
                create_pairing_handler();
                this.pairing_handler.request_pairing();
            }
        }
        
        public override void user_requests_unpair() {
//            ((LanLinkProvider)this.provider).user_requests_unpair(device_id);
            create_pairing_handler();
            this.pairing_handler.unpair();
        }
        
        private void incoming_pair_packet(NetworkProtocol.Packet pkt) {
            create_pairing_handler();
            this.pairing_handler.packet_received(pkt);
        }
        
        private void create_pairing_handler() {
            if (!this.has_pairing_handler()) {
                this.pairing_handler = new Connection.PairingHandler(this);
                debug("Creating pairing handler for %s", this.device_id);
                this.pairing_handler.pairing_error.connect((s,m) => {this.pairing_error(m); });
            }
        }

        private async void send_async(OutputStream output, string sent) throws Error {
            size_t len;
            yield output.write_all_async(sent.data, Priority.DEFAULT_IDLE, cancel_link, out len);
            debug("Packet sent: %s", sent);
        }
        
        public override bool send_packet(NetworkProtocol.Packet input) {
            if (input.has_payload()) {
//                np.setPayloadTransferInfo(sendPayload(np)->transferInfo());
            }

            try {
                string sent = input.serialize() + "\n";
                send_async(this.dos, sent);
            } catch (IOError e) {
                warning("Error receiving packet: %s", e.message);
                this.close();
            }

            //Actually we can't detect if a package is received or not. We keep TCP
            //"ESTABLISHED" connections that look legit (return true when we use them),
            //but that are actually broken (until keepalive detects that they are down).
            bool res = true;
            return res;
        }
        
        private async void monitor() {
            cancel_link.reset();

            // Must use sync callback otherwise input_stream errors are thrown: "Stream has outstanding operation"
            SocketSource source = this.socket.create_source(IOCondition.IN | IOCondition.ERR | IOCondition.HUP);
            source.set_callback( (sock, cond) => {
//                debug("Condition found: %u", cond);
                if (sock.get_available_bytes() > 0 && cond == IOCondition.IN) {
                    this.data_received_sync();
                } else if (IOCondition.HUP in cond || IOCondition.ERR in cond) {
                    this.close();
                    return GLib.Source.REMOVE; // continue watching
                }
                return GLib.Source.CONTINUE; // continue watching
            });
            source_id = source.attach(MainContext.default ());
        }

        private void data_received_sync() {
            string data = null;
            try {
                data = read_line(this.dis);
            } catch (IOError e) {
                warning("Error receiving packet: %s", e.message);
                this.close();
            }

            if (data == null) {
                return;
            }
            debug("Received: %s", data);
            NetworkProtocol.Packet raw_pkt = null;
            try {
                raw_pkt = NetworkProtocol.Packet.unserialize(data);
            } catch (NetworkProtocol.PacketError e) {
                warning("Error unserializing json packet %s", data);
                return;
            }
            packet_received(raw_pkt);
        }
        
        private string? read_line (InputStream input) throws Error {
            var buffer = new uint8[1];
            var sb = new StringBuilder ();
            buffer[0] = '\0';
            while (buffer[0] != '\n') {
                input.read (buffer, cancel_link);
                sb.append_c ((char) buffer[0]);
            }
            return (string) sb.data;
        }

        private void packet_received(NetworkProtocol.Packet raw_pkt) {
            if (raw_pkt.packet_type == NetworkProtocol.PACKET_TYPE_PAIR) {
                //TODO: Handle pair/unpair requests and forward them (to the pairing handler?)
//                ((LanLinkProvider)this.provider).incoming_pair_packet(this, raw_pkt);
                this.incoming_pair_packet(raw_pkt);
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
            } else {
                pkt = raw_pkt;
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
