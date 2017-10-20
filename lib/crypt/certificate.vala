/**
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * AUTHORS
 * Maciek Borzecki <maciek.borzecki (at] gmail.com>
 * <getzze (at] gmail.com> (minor modifications)
 */

namespace Gconnect.Crypt {

    private GnuTLS.X509.PrivateKey generate_private_key() {
        var key = GnuTLS.X509.PrivateKey.create();

        key.generate(GnuTLS.PKAlgorithm.RSA, 2048);

        return key;
    }

    private struct dn_setting {
        string oid;
        string name;
    }
    
    GnuTLS.X509.Certificate generate_self_signed_cert(GnuTLS.X509.PrivateKey key, string common_name) {
        int err;
        var cert = GnuTLS.X509.Certificate.create();
        var now = new DateTime.now_utc();

        cert.set_key(key);
        cert.set_version(3);
        cert.set_activation_time ((time_t)now.to_unix());
        cert.set_expiration_time ((time_t)now.add_years(10).to_unix());
        uint32 serial = Posix.htonl(10);
        cert.set_serial(&serial, sizeof(uint32));

        dn_setting[] dn = {
            dn_setting() { oid=GnuTLS.OID.X520_ORGANIZATION_NAME,
                           name="gconnect"},
            dn_setting() { oid=GnuTLS.OID.X520_ORGANIZATIONAL_UNIT_NAME,
                           name="gconnect"},
            dn_setting() { oid=GnuTLS.OID.X520_COMMON_NAME,
                           name=common_name},
        };
        foreach (var dn_val in dn) {
            err = cert.set_string_dn_by_oid(dn_val.oid, 0, dn_val.name);
            if (err != GnuTLS.ErrorCode.SUCCESS ) {
                warning("set dn failed for OID %s - %s, err: %d\n",
                        dn_val.oid, dn_val.name, err);
            }
        }

        err = cert.set_basic_constraints(1, -1); // CA authority
        if (err != GnuTLS.ErrorCode.SUCCESS) {
            warning("set basic constraint for CA authority failed, err: %d\n", err);
        }
        string[] kps = {GnuTLS.KP.TLS_WWW_CLIENT, GnuTLS.KP.TLS_WWW_SERVER};
        foreach (var kp in kps) {
            err = cert.set_key_purpose_oid(kp, false);
            if (err != GnuTLS.ErrorCode.SUCCESS) {
                warning("set key purpose %s failed, err: %d\n", kp, err);
            }
        }

        var buf = new uint8[8192];
        size_t sz = buf.length;
        err = cert.get_key_id(0, buf, ref sz);
        if (err >= 0) {
            err = cert.set_subject_key_id(buf, sz);
            if (err != GnuTLS.ErrorCode.SUCCESS) {
                warning("set subject key id failed, err: %d\n", err);
            }
        }

        err = cert.sign2(cert, key, GnuTLS.DigestAlgorithm.SHA256, 0);
        GLib.assert(err == GnuTLS.ErrorCode.SUCCESS);

        return cert;
    }

    private uint8[] export_certificate(GnuTLS.X509.Certificate cert) {
        var buf = new uint8[8192];
        size_t sz = buf.length;


        var err = cert.export(GnuTLS.X509.CertificateFormat.PEM, buf, ref sz);
        assert(err == GnuTLS.ErrorCode.SUCCESS);

        debug("actual certificate PEM size: %zu", sz);
        debug("certificate PEM:\n%s", (string)buf);

        // TODO: figure out if this is valid at all
        buf.length = (int) sz;

        return buf;
    }

    private uint8[] export_private_key(GnuTLS.X509.PrivateKey key) {
        var buf = new uint8[8192];
        size_t sz = buf.length;

        var err = key.export_pkcs8(GnuTLS.X509.CertificateFormat.PEM, "",
                                   GnuTLS.X509.PKCSEncryptFlags.PLAIN,
                                   buf, ref sz);
        assert(err == GnuTLS.ErrorCode.SUCCESS);
        debug("actual private key PEM size: %zu", sz);
        debug("private key PEM:\n%s", (string)buf);

        // TODO: figure out if this is valid at all
        buf.length = (int) sz;
        return buf;
    }

    private void export_to_file(string path, uint8[] data) throws Error {
        var f = File.new_for_path(path);

        f.replace_contents(data, "", false,
                           FileCreateFlags.PRIVATE | FileCreateFlags.REPLACE_DESTINATION,
                           null);
    }

    public void generate_key_cert(string key_path, string cert_path, string name) throws Error {
        var key = generate_private_key();
        var cert = generate_self_signed_cert(key, name);

        export_to_file(cert_path, export_certificate(cert));
        export_to_file(key_path, export_private_key(key));
    }

    private GnuTLS.X509.Certificate cert_from_pem(string certificate_pem) {
        var datum = GnuTLS.Datum() { data=certificate_pem.data,
                                     size=certificate_pem.data.length };

        var cert = GnuTLS.X509.Certificate.create();
        var res = cert.import(ref datum, GnuTLS.X509.CertificateFormat.PEM);
        assert(res == GnuTLS.ErrorCode.SUCCESS);
        return cert;
    }

    /**
     * fingerprint_certificate:
     * Produce a SHA1 fingerprint of the certificate
     *
     * @param certificate_pem PEM encoded certificate
     * @return SHA1 fingerprint as bytes
     */
    public uint8[] fingerprint_certificate(string certificate_pem) {
        var cert = cert_from_pem(certificate_pem);

        // TOOD: make digest configurable, for now assume it's SHA1
        var data = new uint8[20];
        size_t sz = data.length;
        var res = cert.get_fingerprint(GnuTLS.DigestAlgorithm.SHA1,
                                       data, ref sz);
        assert(res == GnuTLS.ErrorCode.SUCCESS);
        assert(sz == data.length);

        return data;
    }
}
