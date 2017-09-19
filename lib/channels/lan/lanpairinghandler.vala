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

    public class LanPairingHandler : Connection.PairingHandler {
        private uint timer_id = 0;
        
        public enum InternalPairStatus {
            NOT_PAIRED,
            REQUESTED,
            REQUESTED_BY_PEER,
            PAIRED,
        }

        protected InternalPairStatus status;

        public LanPairingHandler(Connection.DeviceLink link) {
            base(link);
            this.status = InternalPairStatus.NOT_PAIRED;
        }

        // Public methods
        public override void packet_received(NetworkProtocol.Packet pkt) {
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
        
        public override bool request_pairing() {
            if (this.status == InternalPairStatus.PAIRED) {
                pairing_error("%s: Already paired".printf(this.device_link.name));
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
        
        public override bool accept_pairing() {
            var new_pkt = new NetworkProtocol.Packet.pair();
            debug("Pairing handler - accept pairing");
            bool success = this.device_link.send_packet(new_pkt);
            if (success) {
                set_internal_pair_status(InternalPairStatus.PAIRED);
            }
            return success;
        }
        
        public override void reject_pairing() {
            unpair();
        }
        
        public override void unpair() {
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
