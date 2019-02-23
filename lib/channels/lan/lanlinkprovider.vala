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

    private string string_to_locale(string raw_string, ssize_t len = -1) throws ConvertError {
        string data = raw_string;
        unowned string locale;
        bool need_convert = GLib.get_charset (out locale);
        if (need_convert) {
            data = GLib.convert (raw_string, len, locale, "UTF-8");
        }
        return data;
    }

    private string string_from_locale(string text) throws ConvertError {
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

        private LanLinkConfig _config;

        // Private attributes
        private NetworkMonitor monitor;
        private SocketService server;
        private Cancellable server_cancellable;
        private SocketClient client;
        private Cancellable client_cancellable;
        private Socket udp_socket;
        private Socket udp_send_socket;
        private InetSocketAddress udp_address;
        private InetSocketAddress broadcast_address;
        private uint udp_source_id = 0;
        private uint16 tcp_port;

        private HashMap<string, LanConnection.LanDeviceLink> links;

        private bool test_mode;
        private uint combine_broadcasts_timer = 0;

        public override Connection.LinkConfig config {
            get { return this._config; }
            protected set { this._config = value as LanLinkConfig; }
        }

        public LanLinkProvider(bool mode) throws Error {
            this._config = new LanLinkConfig();
            this.tcp_port = 0;
            this.test_mode = mode;

            links = new HashMap<string, LanConnection.LanDeviceLink>();

            InetAddress client_address;
            InetAddress bc_address;
            if (this.test_mode) {
                debug("Test mode activated, broadcast to loopback");
                client_address = new InetAddress.loopback(SocketFamily.IPV4);
                bc_address = new InetAddress.loopback(SocketFamily.IPV4);
            } else {
                client_address = new InetAddress.any(SocketFamily.IPV4);
//                bc_address = new InetAddress.any(SocketFamily.IPV4);
                bc_address = new InetAddress.from_string("255.255.255.255");
            }
            this.udp_address = new InetSocketAddress(client_address, this._config.udp_port);
            this.broadcast_address = new InetSocketAddress(bc_address, this._config.udp_port);

            udp_socket = new Socket(SocketFamily.IPV4, SocketType.DATAGRAM, SocketProtocol.UDP);
            udp_send_socket = new Socket(SocketFamily.IPV4, SocketType.DATAGRAM, SocketProtocol.UDP);
            udp_send_socket.set_broadcast(true);
            udp_send_socket.set_multicast_loopback(false);
            udp_send_socket.set_multicast_ttl(1);

            client = new SocketClient();
            client.set_family(SocketFamily.IPV4);
            client.set_enable_proxy(false);
            // Used to shutdown the client
            client_cancellable = new Cancellable ();
            if (NetworkProtocol.PROTOCOL_VERSION >= MIN_VERSION_WITH_SSL_SUPPORT) {
                // Do no set because it starts TLS session directly, we need first to exchange non-encrypted info
                client.set_tls(false);
                var tls_bkd = TlsBackend.get_default();
                debug("TLS supported: %s -> %s", tls_bkd.supports_tls().to_string(), tls_bkd.get_server_connection_type().name());
            }

            server = new SocketService();
            // Used to shutdown the server
            server_cancellable = new Cancellable ();
            server_cancellable.cancelled.connect (() => {
                server.stop ();
            });
            server.incoming.connect((s, conn, source)=> {
                on_server_connection(conn);
                return false; // continue listenning
            });
            server.set_backlog(10);

            //Detect when a network interface changes status, so we announce ourelves in the new network
            this.monitor = NetworkMonitor.get_default();
            monitor.network_changed.connect((available) => {
                info("Network changed (available: %s)\n", available.to_string ());
                if (available == true) {
                    on_network_change();
                }
            });
        }

        // Public methods
        public override string name { get; protected set; default="LanLinkProvider"; }
        public override int priority { get; protected set; default=PRIORITY_HIGH; }

        public static void configure_tls_connection(TlsConnection conn, string device_id) {
            var config = Config.Config.instance();
            var cert = config.certificate;
            conn.set_certificate(cert);

            try {
                conn.handshake();
            } catch (Error e) {
                warning("Could not realize handshake with %s: %s", device_id, e.message);
            }

            // TODO: check certificate
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

        }

        public static void configure_socket(Socket sock) throws Error {
            // time to start sending keepalive packets (seconds)
            int max_idle = 10;
            sock.set_option(Posix.IPProto.TCP, Posix.TCP_KEEPIDLE, max_idle);
            // interval between keepalive packets after the initial period (seconds)
            int interval = 5;
            sock.set_option(Posix.IPProto.TCP, Posix.TCP_KEEPINTVL, interval);
            // number of missed keepalive packets before disconnecting
            int count = 3;
            sock.set_option(Posix.IPProto.TCP, Posix.TCP_KEEPCNT, count);

            // enable keepalive
            sock.set_keepalive(true);
        }

        public override void on_start() throws Error {
            info("LanLinkProvider on start ...");

            // Bind udp socket
            udp_socket.bind(this.udp_address, true);  // allow_reuse=true
            udp_send_socket.bind(this.udp_address, true);  // allow_reuse=true
            start_udp_watch();
            debug("Bind UDP socket to %s", this.udp_address.to_string());

            // Start server listening
            this.tcp_port = this._config.tcp_range[0];
            while (!server.add_inet_port(this.tcp_port, null)) {
                this.tcp_port++;
                if (this.tcp_port > this._config.tcp_range[1]) { //No ports available?
                    critical("Error opening a port in range %u-%u", this._config.tcp_range[0], this._config.tcp_range[1]);
                    this.tcp_port = 0;
                    return;
                }
            }
            debug("Start TCP server on port %u", this.tcp_port);
            server.start();

            on_network_change();
        }

        public override void on_stop() throws Error  {
            info("... LanLinkProvider on stop");
            stop_udp_watch();
            try {
                udp_socket.close();
            } catch (Error e) {}

            server.stop();
            server_cancellable.cancel();
            client_cancellable.cancel();
        }

        public override void on_network_change() throws Error  {
            if (combine_broadcasts_timer>0) {
                debug("Preventing duplicate broadcasts");
                return;
            }
            // increase this if waiting a single event-loop iteration is not enough
            int timeout_sec = 2;
            combine_broadcasts_timer = GLib.Timeout.add_seconds(timeout_sec, broadcast_to_network, Priority.DEFAULT);
        }

        // Private methods
        private void on_udp_socket_connection(Socket sock, IOCondition condition) {
            SocketAddress sender;
            string data;
            try {
                uint8[] buffer = new uint8[1 << 16]; // Maximum UDP length - we don't loose anything
                sock.receive_from(out sender, buffer);
                data = (string)buffer;
            } catch (Error e) {
                warning("Could not receive datagram from udp connection: " + e.message);
                return;
            }
            InetSocketAddress inet_sender = sender as InetSocketAddress;

//            debug("UDP will be discarded. Received data from %s:%u : %s", inet_sender.address.to_string(), inet_sender.port, data);
            try {
                new_udp_socket_connection.begin(inet_sender, data);
            } catch (Error e) {
                // pass
            }
        }

        private async void new_udp_socket_connection(InetSocketAddress sender, string data) throws Error {
            NetworkProtocol.Packet pkt = null;
            try {
                pkt = NetworkProtocol.Packet.unserialize(data);
            } catch (NetworkProtocol.PacketError e) {
                warning("Error unserializing json packet %s", data);
                return;
            }
            if (pkt.packet_type != NetworkProtocol.PACKET_TYPE_IDENTITY) {
                warning("LanLinkProvider udp socket: Expected identity, received %", pkt.packet_type);
                return;
            }

            string dev_id = pkt.get_device_id();
            if (dev_id == Config.Config.instance().device_id) {
                debug("Ignoring my own broadcast.");
                return;
            }

            uint16 remote_tcp_port = this._config.tcp_range[0]; // Default
            debug("Incoming identity packet: %s", pkt.to_string());
            if (pkt.has_field("tcpPort")) {
                remote_tcp_port = (uint16)pkt.get_int("tcpPort");
            } else {
                warning("Incoming identity packet does not specify a tcpPort, try default: %u", remote_tcp_port);
            }
            if (remote_tcp_port < this._config.tcp_range[0] || remote_tcp_port > this._config.tcp_range[1]) {
                warning("Asking for TCP connection outside of allowed range. Not default behavior, aborting: port %u", remote_tcp_port);
            }

            debug("Received udp identity package from %s, asking for a tcp connection on port %d", dev_id, remote_tcp_port);

            // Wait for connection
            SocketConnection conn;
            try {
                conn = yield client.connect_async(new InetSocketAddress( sender.address, remote_tcp_port), client_cancellable);
            } catch (Error e) {
                warning("Error with early tcp client connection: %s\n", e.message);
                return;
            }

            // Configure TCP socket
            try {
                configure_socket(conn.get_socket());
            } catch (Error e) {
                warning("Error configuring the socket: %s", e.message);
                return;
            }


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
                warning("Error with tcp client connection: %s\n", e.message);
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

        private void on_server_connection(SocketConnection conn) {
            // Configure TCP socket
            try {
                configure_socket(conn.get_socket());
            } catch (Error e) {
                warning("Error configuring the socket: %s", e.message);
                return;
            }

            // Process the request asynchronously
            new_server_connection.begin(conn);
        }

        private async void new_server_connection(SocketConnection conn) {
            debug("New connection to tcp server");
            string req;
            try {
                var buffer = new uint8[1];
                var sb = new StringBuilder ();
                buffer[0] = '\0';
                while (buffer[0] != '\n') {
                    yield conn.input_stream.read_async (buffer, Priority.DEFAULT_IDLE);
                    sb.append_c ((char) buffer[0]);
                }
                req = (string) sb.data;
                if (req == null) {
                    return;
                }
                debug("LanLinkProvider server received reply: %s", req);
            } catch (Error e) {
                warning("Error with server connection: %s\n", e.message);
                return;
            }

            NetworkProtocol.Packet pkt = null;
            try {
                pkt = NetworkProtocol.Packet.unserialize(req);
            } catch (NetworkProtocol.PacketError e) {
                warning("Error unserializing json packet %s", req);
                return;
            }
            if (pkt.packet_type != NetworkProtocol.PACKET_TYPE_IDENTITY) {
                warning("LanLinkProvider server response: Expected identity, received %s", pkt.packet_type);
                return;
            }

            yield connected(conn, pkt, ConnectionStarted.REMOTELY);
        }

        [Callback]
        private void device_link_destroyed(string id) {
            links.unset(id);
//            if (links.has_key(id)) {
//                // PairingHandler depends on DeviceLink, so remove first
//                if (pairing_handlers.has_key(id)) {
//                    pairing_handlers.unset(id);
//                }
//                links.unset(id);
//            }
        }

        private void stop_udp_watch() {
            if (udp_source_id > 0) {
                Source.remove(udp_source_id);
                udp_source_id = 0;
            }
        }

        private void start_udp_watch() {
            stop_udp_watch();
            SocketSource source = udp_socket.create_source(IOCondition.IN);
            source.set_callback( (src, cond) => {
                this.on_udp_socket_connection(src, cond);
                return true; // keep looking for UDP connections
            });
            udp_source_id = source.attach(MainContext.default ());
        }

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

            var addresses = new HashSet<string>();
            addresses.add(udp_address.address.to_string());
            addresses.add_all_array(this._config.ip_discovery);
            addresses.add_all_array(this._config.get_known_ip_addresses());
            foreach (var addr in addresses) {
                broadcast_to_address(sent, new InetSocketAddress.from_string(addr, this._config.udp_port));
            }

            // stop timer
            combine_broadcasts_timer = 0;
            return GLib.Source.REMOVE;
        }

        private async void broadcast_to_address(string sent, SocketAddress addr) {
            try {
                size_t res = udp_send_socket.send_to(addr, sent.data);
                debug("Broadcast to %s: %s (%.0f)", addr.to_string(), sent, res);
            } catch (Error e) {
                warning("Error with udp broadcast: %s\n", e.message);
            }
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

                try {
                    yield encrypted(conn, id, origin);
                } catch (Error e) {
                    warning("Could not initiate the TLS connection: %s", e.message);
                }

            } else {
                if (!myself_allow_encryption) {
                    warning("I am using an old protocol version, no encryption.");
                }
                if (!others_allow_encryption) {
                    warning("%s is using an old protocol version, no encryption.", dev_id);
                }
//                add_link(dev_id, conn.socket, conn, id, origin);
            }
        }

        private async void encrypted(SocketConnection conn, NetworkProtocol.Packet id, ConnectionStarted origin) throws Error {

            var dev_id = id.get_device_id();
            var config = Config.Config.instance();
            var cert = config.certificate;
            TlsConnection tls_conn;
            if (origin == ConnectionStarted.LOCALLY) {
                debug("Start TLS server connection");
                tls_conn = TlsServerConnection.@new(conn, cert);
                (tls_conn as TlsServerConnection).authentication_mode = TlsAuthenticationMode.REQUIRED;
//                    tls_conn.authentication_mode = TlsAuthenticationMode.REQUESTED;
            } else {
                debug("Start TLS client connection");
                tls_conn = TlsClientConnection.@new(conn, conn.get_remote_address());
                (tls_conn as TlsClientConnection).set_use_ssl3(false);
                (tls_conn as TlsClientConnection).set_certificate(cert);
            }
            tls_conn.set_require_close_notify(false);
            tls_conn.accept_certificate.connect((s, cert, err) => {
                return review_certificate(dev_id, s, cert, err);
            });

            debug("Start handshake");
            bool res = yield tls_conn.handshake_async();

            if (res) {
                debug("Socket succesfully established a TLS connection");
                add_link(dev_id, conn.socket, tls_conn, id, origin);
            } else {
                warning("Could not realize the handshake.");
            }
        }

        private bool review_certificate(string device_id, TlsConnection sender, TlsCertificate cert, TlsCertificateFlags errors) {
            try {
                Config.Config.instance().check_certificate(device_id, cert, errors);
            } catch (TlsError e) {
                warning("Received certificate do not correspond to paired device %s. Try unpairing and pairing again.\nError: %s", device_id, e.message);
                return false;
            }
            debug("Accept peer certificate");
            return true;
        }

        // Private methods
        private void add_link(string device_id, Socket sock, TlsConnection tls_conn,
                                NetworkProtocol.Packet pkt, ConnectionStarted origin) {
            debug("Add link to device: %s", device_id);
            LanSocketConnection conn = new LanSocketConnection(sock, tls_conn, origin);

            if (links.has_key(device_id)) {
                debug("device_link already existed, resetting it.");
                links[device_id].reset(conn);
            } else {
                var new_dl = new LanDeviceLink(device_id, this, conn);
                assert(new_dl != null);
                debug("New device_link created");
                new_dl.destroyed.connect(device_link_destroyed);
                links[device_id] = new_dl;
                assert(links[device_id] != null);
            }
            on_connection_received(pkt, links[device_id]);
        }
    }
}
