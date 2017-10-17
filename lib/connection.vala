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

namespace Gconnect.Connection {

//    public class LinkInfo {}  // No need for GLib.Object methods, only struct with inheritance
    public class LinkConfig : GLib.Object {
        public virtual void add_device(DeviceManager.Device dev) {}
        public virtual void remove_device(DeviceManager.Device dev) {}
    }

    public abstract class LinkProvider : GLib.Object {
        public const int PRIORITY_LOW = 0;      //eg: 3g internet
        public const int PRIORITY_MEDIUM = 50;  //eg: internet
        public const int PRIORITY_HIGH = 100;   //eg: lan

        public virtual LinkConfig config { get; protected set; default=new LinkConfig(); }
        public abstract string name {get; protected set; }
        public abstract int priority {get; protected set; }
        
        public signal void on_connection_received(NetworkProtocol.Packet ip, DeviceLink dl);

        public abstract void on_start() throws Error ;
        public abstract void on_stop();
        public abstract void on_network_change();
    }
    
    public abstract class SocketConnectionLink: GLib.Object {
        protected weak GLib.Socket socket;
        protected GLib.IOStream stream;
        protected uint source_id = 0;
        protected GLib.Cancellable cancel_link;
        
        public signal void packet_received(NetworkProtocol.Packet pkt);
        public signal void forced_close();
        
        public SocketConnectionLink() {
            this.cancel_link = new GLib.Cancellable();
            cancel_link.cancelled.connect((s)=> {
                if (source_id > 0) {
                    Source.remove(source_id);
                    source_id = 0;
                }
            });
        }
        
        ~SocketConnectionLink() {
            try {
                close();
            } catch (GLib.Error e) {
                debug("Could not close connection");
            }
        }

        public bool is_closed() {
            if (this.stream != null) {
                return this.stream.is_closed();
            }
            return true;
        }

        public virtual void clean() {
            cancel_link.cancel();
            if (this.stream != null) {
                try {
                    if (!this.stream.is_closed()) { this.stream.close();}
                } catch (IOError e) {
                    debug("Error closing connection: %s\n", e.message);
                }
            }
        }

        public virtual void close() {
            this.clean();
            this.forced_close();
        }

        public void monitor() {
            cancel_link.reset();

            // Must use sync callback otherwise input_stream errors are thrown: "Stream has outstanding operation"
            SocketSource source = this.socket.create_source(IOCondition.IN | IOCondition.ERR | IOCondition.HUP);
            source.set_callback( (sock, cond) => {
                if (sock.get_available_bytes() > 0 && cond == IOCondition.IN) {
                    this.data_received_sync();
                } else if (IOCondition.HUP in cond || IOCondition.ERR in cond) {
                    this.close();
                    return GLib.Source.REMOVE; // stop watching
                }
                return GLib.Source.CONTINUE; // continue watching
            });
            source_id = source.attach(MainContext.default());
        }

        public void unmonitor() {
            cancel_link.cancel();
        }

        public bool send_packet(NetworkProtocol.Packet input) {
            try {
                string sent = input.serialize() + "\n";
                bool res = this.write(sent);
#if DEBUG_BUILD
                // Should not log the content of every packet sent in normal condition
                debug("Packet sent: %s", sent);
#endif
                return res;
            } catch (IOError e) {
                warning("Error sending packet: %s", e.message);
                this.close();
            }
            return false;
        }
        
        public bool write(string sent) throws IOError {
            var output_stream = this.stream.get_output_stream();
            size_t len;
            // DataOutputStream cannot be used here because it takes ownership
            // of the OutputStream and cannot release it afterwards.
            bool res = output_stream.write_all(sent.data, out len, this.cancel_link);
            if (res) {
                res = output_stream.flush();
            }
            return res;
        }

        private void data_received_sync() {
            string data = null;
            try {
                data = this.read_line();
            } catch (Error e) {
                warning("Error receiving packet: %s", e.message);
                this.close();
            }

            if (data == null) {
                return;
            }
            NetworkProtocol.Packet raw_pkt = null;
            try {
                raw_pkt = NetworkProtocol.Packet.unserialize(data);
            } catch (NetworkProtocol.PacketError e) {
                warning("Error unserializing json packet %s", data);
                return;
            }

#if DEBUG_BUILD
            // Should not log the content of every packet received in normal condition
            debug("Packet received: %s", raw_pkt.to_string());
#endif

            packet_received(raw_pkt);
        }
        
        public string? read_line () throws Error {
            var input_stream = this.stream.get_input_stream();
            var buffer = new uint8[1];
            var sb = new StringBuilder ();
            buffer[0] = '\0';
            while (buffer[0] != '\n') {
                input_stream.read (buffer, cancel_link);
                sb.append_c ((char) buffer[0]);
            }
            return (string) sb.data;
        }


    }

    public abstract class DeviceLink : GLib.Object {
        protected weak LinkProvider _link_provider;
        protected PairStatus _pair_status;

        protected PairingHandler? pairing_handler = null;

        public enum PairStatus { NOT_PAIRED, PAIRED }

        public weak LinkProvider provider {
            get {return this._link_provider;}
            private set {this._link_provider = value;}
        }
        public abstract string name { get; protected set;}
        public string device_id { get; protected set;}

        public signal void pairing_request(PairingHandler handler);
        public signal void pairing_request_expired(PairingHandler handler);
        public signal void pair_status_changed(DeviceLink dl, PairStatus status);
        public signal void pairing_error(string mess);
        public signal void received_packet(NetworkProtocol.Packet np);
        public signal void destroyed(string device_id);
        
        public DeviceLink(string id, LinkProvider parent)
                requires (id != "")
        {
            this.device_id = id;
            this._link_provider = parent;
            this._pair_status = PairStatus.NOT_PAIRED;
        }
        
        ~DeviceLink() {
            this.pairing_handler = null;
            destroyed(this.device_id);
        }

        public PairStatus get_pair_status() {
            return _pair_status;
        }

        public virtual void set_pair_status(PairStatus status) {
            set_and_announce_pair_status(status);
        }
        
        protected void set_and_announce_pair_status(PairStatus st) {
            if (_pair_status != st) {
                _pair_status = st;
                pair_status_changed(this, _pair_status);
            }
        }
        
        public abstract bool send_packet(NetworkProtocol.Packet pkt);

        protected void create_pairing_handler() {
            if (!this.has_pairing_handler()) {
                this.pairing_handler = new PairingHandler(this);
                this.pairing_handler.pairing_error.connect((s,m) => {this.pairing_error(m); });
            }
        }

        protected void incoming_pair_packet(NetworkProtocol.Packet pkt) {
            create_pairing_handler();
            this.pairing_handler.packet_received(pkt);
        }
        
        protected void request_pair() {
            create_pairing_handler();
            this.pairing_handler.request_pairing();
        }
        
        protected void request_unpair() {
            create_pairing_handler();
            this.pairing_handler.unpair();
        }

        //user actions
        public virtual void user_requests_pair() {
            request_pair();
        }

        public virtual void user_requests_unpair() {
            request_unpair();
        }

        public virtual bool has_pairing_handler() {
            return (this.pairing_handler != null)?true:false;
        }
        
        public virtual bool user_accepts_pair() {
            if (this.has_pairing_handler()) {
                this.pairing_handler.accept_pairing();
                return true;
            }
            return false;
        }

        public virtual bool user_rejects_pair() {
            if (this.has_pairing_handler()) {
                this.pairing_handler.reject_pairing();
                return true;
            }
            return false;
        }

        public virtual void parse_device_info(ref DeviceManager.DeviceInfo dev) {}
        
//        public virtual DeviceLinkInfo get_info() {
//            var ret = new DeviceLinkInfo();
//            return ret;
//        }
        
        //The daemon will periodically destroy unpaired links if this returns false
        public virtual bool link_should_be_kept_alive() { return false;}
    }
    
    public class PairingHandler : GLib.Object {
        private weak DeviceLink _device_link;
        private uint timer_id = 0;
        private InternalPairStatus status;
        
        public enum InternalPairStatus {
            NOT_PAIRED,
            REQUESTED,
            REQUESTED_BY_PEER,
            PAIRED,
        }
        public signal void pairing_error(string mess);

        public weak DeviceLink device_link {
            get { return _device_link;}
            set { _device_link = value;}
        }

        public PairingHandler(DeviceLink link) {
            this._device_link = link;
            this.status = InternalPairStatus.NOT_PAIRED;
        }

        // Public methods
        public virtual int pairing_timeout_msec() { return 30 * 1000; } // 30 seconds of timeout (default), subclasses that use different values should override

        public void packet_received(NetworkProtocol.Packet pkt) {
            bool? wants_pair = pkt.get_pair_request();
            if (wants_pair == null) {
                return;
            }
            if (wants_pair) {
                if (is_pair_requested())  { //We started pairing
                    debug("Pair answer");
                    set_internal_pair_status(InternalPairStatus.PAIRED);
                } else {
                    debug("Pair request");
                    if (is_paired()) { //I'm already paired, but they think I'm not
                        accept_pairing();
                        return;
                    }
                    set_internal_pair_status(InternalPairStatus.REQUESTED_BY_PEER);
                }
            } else {  // wants_pair==false
                debug("Unpair request");
                
                if (is_pair_requested())  {
                    pairing_error(_("Canceled by other peer"));
                }
                set_internal_pair_status(InternalPairStatus.NOT_PAIRED);
            }
        }
        
        public bool request_pairing() {
            if (this.status == InternalPairStatus.PAIRED) {
                pairing_error(_("Already paired") + ": %s".printf(this.device_link.name));
                return false;
            }
            if (this.status == InternalPairStatus.REQUESTED_BY_PEER) {
                debug("%s: Pairing already started by the other end, accepting their request.", this.device_link.name);
                return accept_pairing();
            }

            var new_pkt = new NetworkProtocol.Packet.pair();
            debug("Pairing handler - ask for pairing");
            bool success = this.device_link.send_packet(new_pkt);
            if (success) {
                set_internal_pair_status(InternalPairStatus.REQUESTED);
            }
            return success;
        }
        
        public bool accept_pairing() {
            var new_pkt = new NetworkProtocol.Packet.pair();
            debug("Pairing handler - accept pairing");
            bool success = this.device_link.send_packet(new_pkt);
            if (success) {
                set_internal_pair_status(InternalPairStatus.PAIRED);
            }
            return success;
        }
        
        public void reject_pairing() {
            unpair();
        }
        
        public void unpair() {
            var new_pkt = new NetworkProtocol.Packet.pair(false);
            debug("Pairing handler - ask for unpairing");
            this.device_link.send_packet(new_pkt);
            set_internal_pair_status(InternalPairStatus.NOT_PAIRED);
        }

        public bool is_pair_requested() { return this.status == InternalPairStatus.REQUESTED; }
        public bool is_paired() { return this.status == InternalPairStatus.PAIRED; }

        [Callback]
        private bool pairing_timeout() {
            this.unpair();
            this.pairing_error(_("Timed out"));
            // stop timer
            this.timer_id = 0;
            return GLib.Source.REMOVE;
        }

        protected void set_internal_pair_status(InternalPairStatus status) {
            if (this.timer_id>0) {
                GLib.Source.remove(this.timer_id);
                this.timer_id = 0;
            }
            if (status == InternalPairStatus.REQUESTED || status == InternalPairStatus.REQUESTED_BY_PEER) {
                this.timer_id = Timeout.add(this.pairing_timeout_msec(), this.pairing_timeout, Priority.LOW);
            }

            if (this.status == InternalPairStatus.REQUESTED_BY_PEER &&
                    (status == InternalPairStatus.NOT_PAIRED || status == InternalPairStatus.PAIRED)) {
                this.device_link.pairing_request_expired(this);
            } else if (status == InternalPairStatus.REQUESTED_BY_PEER) {
                this.device_link.pairing_request(this);
            }

            this.status = status;
            if (status == InternalPairStatus.PAIRED) {
                this.device_link.set_pair_status(Connection.DeviceLink.PairStatus.PAIRED);
            } else {
                this.device_link.set_pair_status(Connection.DeviceLink.PairStatus.NOT_PAIRED);
            }
        }
    }
} 
