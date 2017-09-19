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

    public abstract class LinkProvider : GLib.Object {
        public const int PRIORITY_LOW = 0;      //eg: 3g internet
        public const int PRIORITY_MEDIUM = 50;  //eg: internet
        public const int PRIORITY_HIGH = 100;   //eg: lan

        public abstract string name {get; protected set; }
        public abstract int priority {get; protected set; }
        
        public signal void on_connection_received(NetworkProtocol.Packet ip, DeviceLink dl);

        public abstract void on_start() throws Error ;
        public abstract void on_stop();
        public abstract void on_network_change();
    }
    

    public abstract class DeviceLink : GLib.Object {
        protected weak LinkProvider _link_provider;
        protected PairStatus _pair_status;
        protected GLib.Cancellable cancel_link;

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
            this.cancel_link = new GLib.Cancellable();
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

        //user actions
        public abstract void user_requests_pair();
        public abstract void user_requests_unpair();

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
        
        //The daemon will periodically destroy unpaired links if this returns false
        public virtual bool link_should_be_kept_alive() { return false;}
    }
    
    public abstract class PairingHandler : GLib.Object {
        protected weak DeviceLink _device_link;

        public weak DeviceLink device_link {
            get { return _device_link;}
            set { _device_link = value;}
        }

        public signal void pairing_error(string mess);
        
        public PairingHandler(DeviceLink parent) {
            this._device_link = parent;
        }

        public abstract void packet_received(NetworkProtocol.Packet pkt);
        public abstract void unpair();
        public virtual int pairing_timeout_msec() { return 30 * 1000; } // 30 seconds of timeout (default), subclasses that use different values should override

        public abstract bool request_pairing();
        public abstract bool accept_pairing();
        public abstract void reject_pairing();
    }
} 
