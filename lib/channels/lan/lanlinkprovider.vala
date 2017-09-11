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
//using Posix;
// using Connection;
// using DeviceManager;
// using Config;

namespace Gconnect.LanConnection {
    uint MIN_VERSION_WITH_SSL_SUPPORT = 6;
    
    public enum ConnectionStarted { LOCALLY, REMOTELY }

    private string string_to_locale(string raw_string, ssize_t len = -1) {
        string data = raw_string;
        unowned string locale;
        bool need_convert = GLib.get_charset (out locale);
        if (need_convert) {
            data = GLib.convert (raw_string, len, locale, "UTF-8");
        }
        return data;
    }

    private string string_from_locale(string text) {
        unowned string locale;
        string data = text;
        bool need_convert = GLib.get_charset (out locale);
        if (need_convert) {
            data = GLib.convert ( text, text.length, "UTF-8", locale);
        }       
        return data;
    }

    public class LanLinkProvider : Connection.LinkProvider {
        // Public attributes
        public const uint16 UDP_PORT = 1716;
        public const uint16 MIN_TCP_PORT = 1716;
        public const uint16 MAX_TCP_PORT = 1764;
        private uint16 tcp_port;

        // Private attributes
        private SocketService server;
        private Cancellable server_cancellable;
        private SocketClient client;
        private Cancellable client_cancellable;
        private Socket udp_socket;
        private InetSocketAddress udp_address;
        private InetSocketAddress broadcast_address;
        private uint udp_source_id = 0;
        
        private HashMap<string, LanConnection.LanDeviceLink> links;
        private HashMap<string, LanConnection.LanPairingHandler> pairing_handlers;

        private bool test_mode;
        private uint combine_broadcasts_timer = 0;


        public LanLinkProvider(bool mode) {
            this.tcp_port = 0;
            this.test_mode = mode;
            
            links = new HashMap<string, LanConnection.LanDeviceLink>();
            pairing_handlers = new HashMap<string, LanConnection.LanPairingHandler>();

            InetAddress client_address;
            InetAddress bc_address;
            if (this.test_mode) {
                debug("Test mode activated, broadcast to loopback");
                client_address = new InetAddress.loopback(SocketFamily.IPV4);
                bc_address = new InetAddress.loopback(SocketFamily.IPV4);
            } else {
                client_address = new InetAddress.any(SocketFamily.IPV4);
                bc_address = new InetAddress.any(SocketFamily.IPV4);
//                bc_address = new InetAddress.from_string("255.255.255.255");
            }
            this.udp_address = new InetSocketAddress(client_address, UDP_PORT);
            this.broadcast_address = new InetSocketAddress(bc_address, UDP_PORT);

            udp_socket = new Socket(SocketFamily.IPV4, SocketType.DATAGRAM, SocketProtocol.UDP);
            udp_socket.set_broadcast(true);
            udp_socket.set_multicast_loopback(false);
            udp_socket.set_multicast_ttl(2);
            
            client = new SocketClient();
            client.set_family(SocketFamily.IPV4);
            client.set_enable_proxy(false);
            // Used to shutdown the client
            client_cancellable = new Cancellable ();
            if (NetworkProtocol.PROTOCOL_VERSION >= MIN_VERSION_WITH_SSL_SUPPORT) {
                client.set_tls(true);
                client.set_tls_validation_flags(TlsCertificateFlags.VALIDATE_ALL);
            }
            
            server = new SocketService();
            // Used to shutdown the server
            server_cancellable = new Cancellable ();
            server_cancellable.cancelled.connect (() => {
                server.stop ();
            });
            server.incoming.connect(on_server_connection);
            server.set_backlog(10);
            
        }
        
        // Public methods
        public override string name { get; protected set; default="LanLinkProvider"; }
        public override int priority { get; protected set; default=PRIORITY_HIGH; }
        
        public void user_requests_pair(string device_id) {
            var ph = create_pairing_handler(links[device_id]);
            ph.request_pairing();
        }
        
        public void user_requests_unpair(string device_id) {
            var ph = create_pairing_handler(links[device_id]);
            ph.unpair();
        }
        
        public void incoming_pair_packet(Connection.DeviceLink dl, NetworkProtocol.Packet pkt) {
            var ph = create_pairing_handler(dl);
            ph.packet_received(pkt);
        }

        public static void configure_tls_connection(TlsConnection conn, string device_id) {
            var config = Config.Config.instance();
            var cert = config.certificate;
            conn.set_certificate(cert);
            
            try {
                conn.handshake();
            } catch (Error e) {
                warning("Could not realize handshake with %s: %s", device_id, e.message);
            }
//            warning("Certificate:\n%s", cert.certificate_pem);
            
//            // Setting supported ciphers manually
//            // Top 3 ciphers are for new Android devices, botton two are for old Android devices
//            // FIXME : These cipher suites should be checked whether they are supported or not on device
//            QList<QSslCipher> socketCiphers;
//            socketCiphers.append(QSslCipher(QStringLiteral("ECDHE-ECDSA-AES256-GCM-SHA384")));
//            socketCiphers.append(QSslCipher(QStringLiteral("ECDHE-ECDSA-AES128-GCM-SHA256")));
//            socketCiphers.append(QSslCipher(QStringLiteral("ECDHE-RSA-AES128-SHA")));
//            socketCiphers.append(QSslCipher(QStringLiteral("RC4-SHA")));
//            socketCiphers.append(QSslCipher(QStringLiteral("RC4-MD5")));

//            // Configure for ssl
//            QSslConfiguration sslConfig;
//            sslConfig.setCiphers(socketCiphers);
//            sslConfig.setProtocol(QSsl::TlsV1_0);

//            socket->setSslConfiguration(sslConfig);
//            socket->setLocalCertificate(KdeConnectConfig::instance()->certificate());
//            socket->setPrivateKey(KdeConnectConfig::instance()->privateKeyPath());
//            socket->setPeerVerifyName(deviceId);

//            bool is_device_paired = config.get_paired_devices().contains(dev_id);
//            if (is_device_paired) {
//                QString certString = KdeConnectConfig::instance()->getDeviceProperty(deviceId, QStringLiteral("certificate"), QString());
//                socket->addCaCertificate(QSslCertificate(certString.toLatin1()));
//                socket->setPeerVerifyMode(QSslSocket::VerifyPeer);
//            } else {
//                socket->setPeerVerifyMode(QSslSocket::QueryPeer);
//            }

//            //Usually SSL errors are only bad for trusted devices. Uncomment this section to log errors in any case, for debugging.
//            //QObject::connect(socket, static_cast<void (QSslSocket::*)(const QList<QSslError>&)>(&QSslSocket::sslErrors), [](const QList<QSslError>& errors)
//            //{
//            //    Q_FOREACH (const QSslError &error, errors) {
//            //        qCDebug(KDECONNECT_CORE) << "SSL Error:" << error.errorString();
//            //    }
//            //});
        }
        
        public static void configure_socket(Socket sock) {
            //Posix.IPProto.TCP = 6
            //Posix.TCP_KEEPIDLE = 4
            //Posix.TCP_KEEPINTVL = 5
            //Posix.TCP_KEEPCNT = 6
            try {
                // time to start sending keepalive packets (seconds)
                int max_idle = 10;
                sock.set_option(6, 4, max_idle);
                // interval between keepalive packets after the initial period (seconds)
                int interval = 5;
                sock.set_option(6, 5, interval);
                // number of missed keepalive packets before disconnecting
                int count = 3;
                sock.set_option(6, 6, count);

                // enable keepalive
                sock.set_keepalive(true);
            } catch (Error e) {
                error("Error configuring the socket: %s", e.message);
            }
        }

        // Public slots
        [Callback]
        public override void on_start() {
            // Bind udp socket
            try {
                bool success = udp_socket.bind(this.udp_address, true);  // allow_reuse=true
                assert(success);
                SocketSource source = udp_socket.create_source(IOCondition.IN);
                source.set_callback( (src, cond) => {
                    return this.on_udp_socket_connection(src, cond);
                });
                udp_source_id = source.attach(MainContext.default ());
            } catch (Error e) {
                error("Could not start udp socket: " + e.message);
            }            
            debug("LanLinkProvider on start ...");
            
            // Start server listening
            this.tcp_port = MIN_TCP_PORT;
            while (!server.add_inet_port(this.tcp_port, null)) {
                this.tcp_port++;
                if (this.tcp_port > MAX_TCP_PORT) { //No ports available?
                    critical("Error opening a port in range %u-%u", MIN_TCP_PORT, MAX_TCP_PORT);
                    this.tcp_port = 0;
                    return;
                }
            }
            debug("Start TCP server on port %u", this.tcp_port);
            server.start();
            
            on_network_change();
        }

        [Callback]
        public override void on_stop() {
            debug("... LanLinkProvider on stop");
            if (udp_source_id > 0) {
                Source.remove(udp_source_id);
                udp_source_id = 0;
            }
            udp_socket.close();
            
            server.stop();
            server_cancellable.cancel();
            client_cancellable.cancel();
        }

        [Callback]
        public override void on_network_change() {
            if (combine_broadcasts_timer>0) {
                debug("Preventing duplicate broadcasts");
                return;
            }
            // increase this if waiting a single event-loop iteration is not enough
            int timeout_sec = 2;
            combine_broadcasts_timer = GLib.Timeout.add_seconds(timeout_sec, broadcast_to_network, Priority.DEFAULT);
        }

        private async void connected(SocketConnection conn, NetworkProtocol.Packet id, ConnectionStarted origin) {
            string dev_id = id.get_device_id();
            
            bool myself_allow_encryption = NetworkProtocol.PROTOCOL_VERSION >= MIN_VERSION_WITH_SSL_SUPPORT;
            bool others_allow_encryption = id.get_int("protocolVersion") >= MIN_VERSION_WITH_SSL_SUPPORT;
            if (myself_allow_encryption && others_allow_encryption) {
                debug((origin == ConnectionStarted.LOCALLY) ?
                        "Starting server ssl (but I'm the client TCP socket)" :
                        "Starting client ssl (but I'm the server TCP socket)"
                );

                encrypted(conn, id, origin);
//                connect(socket, &QSslSocket::encrypted, this, &LanLinkProvider::encrypted);
//                if (is_device_paired) {
//                    connect(socket, SIGNAL(sslErrors(QList<QSslError>)), this, SLOT(sslErrors(QList<QSslError>)));
//                }
//                socket->startClientEncryption();

            } else {
                if (!myself_allow_encryption) {
                    warning("I am using an old protocol version, no encryption.");
                }
                if (!others_allow_encryption) {
                    warning("%s is using an old protocol version, no encryption.", dev_id);
                }
                add_link(dev_id, conn, id, origin);
            }
        }

        private async void encrypted(SocketConnection conn, NetworkProtocol.Packet id, ConnectionStarted origin) {

            // TODO: transfer conn.IOStream to a TlsClientConnection or TlsServerConnection
            if (origin == ConnectionStarted.LOCALLY) {
                var addr = conn.get_remote_address ();
                try {
                    debug("Allow TLS connections");
//                    client.set_tls(true);
//                    TlsClientConnection tls_conn = (TlsClientConnection)conn;
                    var tls_conn = TlsClientConnection.@new(conn, null);
                    tls_conn.accept_certificate.connect((s, cert, e)=> {
                        switch (e) {
                        case TlsCertificateFlags.UNKNOWN_CA:
                            debug("TLS error: %s", TlsCertificateFlags.UNKNOWN_CA.to_string());
                            break;
                        case TlsCertificateFlags.BAD_IDENTITY:
                            debug("TLS error: %s", TlsCertificateFlags.BAD_IDENTITY.to_string());
                            break;
                        case TlsCertificateFlags.NOT_ACTIVATED:
                            debug("TLS error: %s", TlsCertificateFlags.NOT_ACTIVATED.to_string());
                            break;
                        case TlsCertificateFlags.EXPIRED:
                            debug("TLS error: %s", TlsCertificateFlags.EXPIRED.to_string());
                            break;
                        case TlsCertificateFlags.REVOKED:
                            debug("TLS error: %s", TlsCertificateFlags.REVOKED.to_string());
                            break;
                        case TlsCertificateFlags.INSECURE:
                            debug("TLS error: %s", TlsCertificateFlags.INSECURE.to_string());
                            break;
                        case TlsCertificateFlags.GENERIC_ERROR:
                            debug("TLS error: %s", TlsCertificateFlags.GENERIC_ERROR.to_string());
                            break;
                        case TlsCertificateFlags.VALIDATE_ALL:
                            debug("TLS error: %s", TlsCertificateFlags.VALIDATE_ALL.to_string());
                            break;
                        }
                        return false;
                    });
                    
    //                conn = yield client.connect_to_host_async(sender.to_string(), remote_tcp_port, client_cancellable);
                    configure_tls_connection( tls_conn, id.get_device_id());
                } catch (Error e) {
                    error("Error with TLS connection: %s\n", e.message);
                } finally {
                    client.set_tls(false);
                }

            }

//            QSslSocket* socket = qobject_cast<QSslSocket*>(sender());
//            if (!socket) return;
//            disconnect(socket, &QSslSocket::encrypted, this, &LanLinkProvider::encrypted);
//            disconnect(socket, SIGNAL(sslErrors(QList<QSslError>)), this, SLOT(sslErrors(QList<QSslError>)));

//            Q_ASSERT(socket->mode() != QSslSocket::UnencryptedMode);
//            LanDeviceLink::ConnectionStarted connectionOrigin = (socket->mode() == QSslSocket::SslClientMode)? LanDeviceLink::Locally : LanDeviceLink::Remotely;

//            NetworkPackage* receivedPackage = receivedIdentityPackages[socket].np;
//            const QString& deviceId = receivedPackage->get<QString>(QStringLiteral("deviceId"));
            debug("Socket succesfully stablished an SSL connection");
//            add_link(dev_id, tls_conn, id, origin);
        }

        [Callback]
        public void connect_error() {
//            QSslSocket* socket = qobject_cast<QSslSocket*>(sender());
//            if (!socket) return;
//            disconnect(socket, &QAbstractSocket::connected, this, &LanLinkProvider::connected);
//            disconnect(socket, SIGNAL(error(QAbstractSocket::SocketError)), this, SLOT(connectError()));

//            qCDebug(KDECONNECT_CORE) << "Fallback (1), try reverse connection (send udp packet)" << socket->errorString();
//            NetworkPackage np(QLatin1String(""));
//            NetworkPackage::createIdentityPackage(&np);
//            np.set(QStringLiteral("tcpPort"), mTcpPort);
//            mUdpSocket.writeDatagram(np.serialize(), receivedIdentityPackages[socket].sender, UDP_PORT);

//            //The socket we created didn't work, and we didn't manage
//            //to create a LanDeviceLink from it, deleting everything.
//            delete receivedIdentityPackages.take(socket).np;
//            delete socket;
        }
        
        // Private slots
        [Callback]
        private bool on_udp_socket_connection(Socket sock, IOCondition condition) {
            SocketAddress sender;
            string data;
            try {
                uint8[] buffer = new uint8[1 << 16]; // Maximum UDP length - we don't loose anything
                ssize_t read = sock.receive_from(out sender, buffer);
                data = (string)buffer;
            } catch (Error e) {
                error("Could not receive datagram from udp connection: " + e.message);
            }
            InetSocketAddress inet_sender = sender as InetSocketAddress;
            
//            debug("UDP will be discarded. Received data from %s:%u : %s", inet_sender.address.to_string(), inet_sender.port, data);
            try {
                    new_udp_socket_connection.begin(inet_sender, data);
            } catch (Error e) {
                // pass
            }
            return true; // keep looking for UDP connections
        }
    
        private async void new_udp_socket_connection(InetSocketAddress sender, string data) {
            var pkt = NetworkProtocol.Packet.unserialize(data);
            
            if (pkt == null) {
                warning("The packet is malformed");
                return;
            } else if (pkt.packet_type != NetworkProtocol.PACKET_TYPE_IDENTITY) {
                warning("LanLinkProvider/newConnection: Expected identity, received %", pkt.packet_type);
                return;
            }
            
            string dev_id = pkt.get_device_id();
            if (dev_id == Config.Config.instance().device_id) {
                debug("Ignoring my own broadcast.");
                return;
            }

            uint16 remote_tcp_port = UDP_PORT; // Default
            debug("Incoming identity packet: %s", pkt.to_string());
            if (pkt.has_field("tcpPort")) {
                remote_tcp_port = (uint16)pkt.get_int("tcpPort");
            } else {
                warning("Incoming identity packet does not specify a tcpPort, try default: %u", remote_tcp_port);
            }
            if (remote_tcp_port < MIN_TCP_PORT || remote_tcp_port > MAX_TCP_PORT) {
                warning("Asking for TCP connection outside of allowed range. Not default behavior, aborting: port %u", remote_tcp_port);
            }

            debug("Received udp identity package from %s, asking for a tcp connection on port %d", dev_id, remote_tcp_port);

            // Wait for connection
            SocketConnection conn;
            try {
                conn = yield client.connect_async(new InetSocketAddress( sender.address, remote_tcp_port), client_cancellable);
            } catch (Error e) {
                error("Error with early tcp client connection: %s\n", e.message);
            }

            // Configure TCP socket
            configure_socket(conn.get_socket());
            
            // If network is on ssl, do not believe when they are connected, believe when handshake is completed
            bool res = false;
            var new_pkt = new NetworkProtocol.Packet.identity();
            string sent = new_pkt.serialize() + "\n";
            try {
                // DataOutputStream cannot be used here because it takes ownership
                // of the OutputStream and cannot release it afterwards.
                size_t len;
                res = conn.output_stream.write_all(sent.data, out len);
                if (res) {
                    res = conn.output_stream.flush();
                }
            } catch (IOError e) {
                error("Error with tcp client connection: %s\n", e.message);
            }

            // Configure the successful connection or fallback to udp.
            if (res) {
                yield connected(conn, pkt, ConnectionStarted.LOCALLY);
            } else {
                //I think this will never happen, but if it happens the deviceLink
                //(or the socket that is now inside it) might not be valid. Delete them.
                debug("Fallback (2), try reverse connection (send udp packet)");
                udp_socket.send_to(conn.get_remote_address(), sent.data);
            }

        }    
        
        [Callback]
        private bool on_server_connection(SocketConnection conn) {
            // Configure TCP socket
            configure_socket(conn.get_socket());
            // Process the request asynchronously
            new_server_connection.begin(conn);
            return true;
        }

        private async void new_server_connection(SocketConnection conn) {
            debug("New connection to tcp server");
            string req;
            try {
                var dis = new DataInputStream (conn.input_stream);
                req = yield dis.read_line_async(Priority.HIGH_IDLE);
                debug("LanLinkProvider server received reply: %s", req);
            } catch (Error e) {
                error("Error with server connection: %s\n", e.message);
            }   
            var pkt = NetworkProtocol.Packet.unserialize(req);
            if (pkt==null) {
                return;
            } else if (pkt.packet_type != NetworkProtocol.PACKET_TYPE_IDENTITY) {
                warning("LanLinkProvider/newConnection: Expected identity, received %", pkt.packet_type);
                return;
            }

            string dev_id = pkt.get_device_id();
 
            yield connected(conn, pkt, ConnectionStarted.REMOTELY);
 
        }
       
        [Callback]
        private void device_link_destroyed(string id) {
            if (links.has_key(id)) {
                // PairingHandler depends on DeviceLink, so remove first
                if (pairing_handlers.has_key(id)) {
                    pairing_handlers.unset(id);
                }
                links.unset(id);
            }
        }
        
//        [Callback]
//        private void ssl_errors(const QList<QSslError>& errors);
        
        [Callback]
        private bool broadcast_to_network() {
            if (!server.is_active()) {
                //Server not started
                return GLib.Source.CONTINUE;
            }
            assert(this.tcp_port != 0);


            var pkt = new NetworkProtocol.Packet.identity();
            pkt.set_int("tcpPort", this.tcp_port);

            debug("Broadcasting identity packet");
            string sent = pkt.serialize() + "\n";
            broadcast_to_address(sent, broadcast_address);
            
            // stop timer
            combine_broadcasts_timer = 0;
            return GLib.Source.REMOVE;
        }

        private async void broadcast_to_address(string sent, SocketAddress addr) {
            try {
                udp_socket.send_to(addr, sent.data);
                debug("Broadcast to %s", addr.to_string());
            } catch (Error e) {
                warning("Error with udp broadcast: %s\n", e.message);
            }
        }
        

        // Private methods
//        private void on_network_configuration_changed(const QNetworkConfiguration &config);
        
        private LanPairingHandler create_pairing_handler(Connection.DeviceLink link) {
            if (!pairing_handlers.has_key(link.device_id)) {
                var ph = new LanPairingHandler(link);
                debug("Creating pairing handler for %s", link.device_id);
                ph.pairing_error.connect((s,m) => {link.pairing_error(m); });
                pairing_handlers[link.device_id] = (owned) ph;
            }
            return pairing_handlers[link.device_id];
        }

        private void add_link(string device_id, SocketConnection sc, 
                                NetworkProtocol.Packet pkt, ConnectionStarted origin) {
            // Socket disconnection will now be handled by LanDeviceLink
//            disconnect(socket, &QAbstractSocket::disconnected, socket, &QObject::deleteLater);
            debug("Add link to device: %s", device_id);

            if (links.has_key(device_id)) {
                debug("device_link already existed, resetting it.");
                links[device_id].reset(sc, origin);
//                bool is_paired = Config.Config.instance().is_paired(device_id);
//                debug("Device pair status: %s", is_paired.to_string());
//                links[device_id].set_pair_status(is_paired?
//                        Connection.DeviceLink.PairStatus.PAIRED :
//                        Connection.DeviceLink.PairStatus.NOT_PAIRED);
            } else {
                var new_dl = new LanDeviceLink(device_id, this, sc, origin);
                assert(new_dl != null);
                debug("New device_link created");
                new_dl.destroyed.connect(device_link_destroyed);
                if (pairing_handlers.has_key(device_id)) {
                    //We shouldn't have a pairinghandler if we didn't have a link.
                    //Crash if debug, recover if release (by setting the new devicelink to the old pairinghandler)
                    pairing_handlers[device_id].device_link = new_dl;
                }
                links[device_id] = new_dl;
                assert(links[device_id] != null);
                on_connection_received(pkt, links[device_id]);
            }
        }
    }
} 
