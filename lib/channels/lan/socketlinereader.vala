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

    public class SocketLineReader : GLib.Object {
        private QSslSocket* mSocket;

        public signal void ready_read();

        public SocketLineReader(QSslSocket* socket);

        public string read() { return mPackages.dequeue(); }
        public async void write(string data) { return mSocket->write(data); }
//        public QHostAddress peerAddress() const { return mSocket->peerAddress(); }
//        public QSslCertificate peerCertificate() const { return mSocket->peerCertificate(); }
//        public qint64 bytesAvailable() const { return mPackages.size(); }

        
        [Callback]
        private void data_received();


    }
}
