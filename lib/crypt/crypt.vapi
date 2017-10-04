
using GnuTLS.X509;

[CCode (cheader_filename = "crypt.h")]
namespace Gconnect.Crypt {
    public PrivateKey import_private_key_from_pem_file(string path);
    public Certificate import_certificate_from_pem_file(string path);
    public bool export_private_key_to_pem_file(PrivateKey key, string path);
    public bool export_certificate_to_pem_file(Certificate crt, string path);
    public Certificate certificate_create(PrivateKey key, uint8 serial);

}

