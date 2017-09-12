/* ex:ts=4:sw=4:sts=4:et */
/* -*- tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*- */
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
 */
#include <uuid/uuid.h>
#include <openssl/rsa.h>
#include <openssl/bio.h>
#include <openssl/pem.h>
#include <openssl/x509v3.h>
#include <string.h>
#include "mconn-crypt.h"

/* encrypted data padding */
#define MCONN_CRYPT_RSA_PADDING RSA_PKCS1_PADDING

typedef struct _MconnCryptPrivate      MconnCryptPrivate;

/**
 * MconnCrypt:
 *
 * A simple wrapper for cypto operations.
 **/

struct _MconnCrypt
{
    GObject parent;
    MconnCryptPrivate *priv;
};

struct _MconnCryptPrivate
{
    RSA        *key;           /* RSA key wrapper */
    X509       *cert;          /* Certificate wrapper */
};

static void mconn_crypt_dispose (GObject *object);
static void mconn_crypt_finalize (GObject *object);
static gchar *__mconn_get_public_key_as_pem(MconnCryptPrivate *priv);
static gchar *__mconn_get_uuid(MconnCryptPrivate *priv);
static gboolean __mconn_load_key(MconnCryptPrivate *priv, const char *path);
static gboolean __mconn_load_cert(MconnCryptPrivate *priv, const char *path);
static gboolean __mconn_generate_key_at_path(const char *path);
static gboolean __mconn_generate_certificate_at_path(const char *key_path, const char *cert_path,
                const char *OrganizationName, const char *OrganizationUnit, int YearsValid);
static int __mconn_certificate_add_ext(X509 *cert, int nid, char *value);

G_DEFINE_TYPE_WITH_PRIVATE (MconnCrypt, mconn_crypt, G_TYPE_OBJECT);

static void
mconn_crypt_class_init (MconnCryptClass *klass)
{
    GObjectClass *gobject_class = (GObjectClass *)klass;

    gobject_class->dispose = mconn_crypt_dispose;
    gobject_class->finalize = mconn_crypt_finalize;
}

static void
mconn_crypt_init (MconnCrypt *self)
{
    g_debug("mconn-crypt: new instance");
    self->priv = mconn_crypt_get_instance_private(self);
}

static void
mconn_crypt_dispose (GObject *object)
{
    MconnCrypt *self = (MconnCrypt *)object;

    if (self->priv->key != NULL)
    {
        RSA_free(self->priv->key);
        self->priv->key = NULL;
    }

    G_OBJECT_CLASS (mconn_crypt_parent_class)->dispose (object);
}

static void
mconn_crypt_finalize (GObject *object)
{
    MconnCrypt *self = (MconnCrypt *)object;

    g_signal_handlers_destroy (object);
    G_OBJECT_CLASS (mconn_crypt_parent_class)->finalize (object);
}

MconnCrypt *mconn_crypt_new_for_key_path(const char *path)
{

    MconnCrypt *self = g_object_new(MCONN_TYPE_CRYPT, NULL);

    if (g_file_test(path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_debug("mconn-crypt: generate new private key at path %s", path);
        __mconn_generate_key_at_path(path);
    }

    if (__mconn_load_key(self->priv, path) == FALSE)
    {
        mconn_crypt_unref(self);
        return NULL;
    }

    return self;
}

MconnCrypt *mconn_crypt_new_for_paths(const char *key_path, const char *cert_path)
{
    MconnCrypt *self = mconn_crypt_new_for_key_path(key_path);
    g_assert(self);

    
    g_assert(self->priv);
    g_assert(self->priv->key);
    
    if (g_file_test(cert_path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_debug("mconn-crypt: generate new certificate at path %s", cert_path);
        __mconn_generate_certificate_at_path(key_path, cert_path, "KDE", "KDE Connect", 10);
    }

    if (__mconn_load_cert(self->priv, cert_path) == FALSE)
    {
        mconn_crypt_unref(self);
        return NULL;
    }

    return self;
}

MconnCrypt * mconn_crypt_ref(MconnCrypt *self)
{
    g_assert(IS_MCONN_CRYPT(self));
    return MCONN_CRYPT(g_object_ref(self));
}

void mconn_crypt_unref(MconnCrypt *self)
{
    if (self != NULL)
    {
        g_assert(IS_MCONN_CRYPT(self));
        g_object_unref(self);
    }
}

GByteArray * mconn_crypt_decrypt(MconnCrypt *self, GBytes *data, GError **err)
{
    g_assert(IS_MCONN_CRYPT(self));
    g_assert(self->priv->key);

    g_debug("decrypt: %zu bytes of data", g_bytes_get_size(data));

    g_assert_cmpint(g_bytes_get_size(data), ==, RSA_size(self->priv->key));

    /* decrypted data is less than RSA_size() long */
    gsize out_buf_size = RSA_size(self->priv->key);
    GByteArray *out_data = g_byte_array_sized_new(out_buf_size);

    int dec_size;
    dec_size = RSA_private_decrypt(g_bytes_get_size(data),
                                   g_bytes_get_data(data, NULL),
                                   (unsigned char *)out_data->data,
                                   self->priv->key,
                                   MCONN_CRYPT_RSA_PADDING);
    g_debug("decrypted size: %d", dec_size);
    g_assert(dec_size != -1);

    g_byte_array_set_size(out_data, dec_size);

    return out_data;
}

gchar *mconn_crypt_get_public_key_pem(MconnCrypt *self)
{
    g_assert(IS_MCONN_CRYPT(self));
    g_assert(self->priv);
    g_assert(self->priv->key);
    return __mconn_get_public_key_as_pem(self->priv);
}

gchar *mconn_crypt_get_uuid(MconnCrypt *self)
{
    g_assert(IS_MCONN_CRYPT(self));
    g_assert(self->priv);
    g_assert(self->priv->cert);
    return __mconn_get_uuid(self->priv);
}

/**
 *
 */
static gchar *__mconn_get_public_key_as_pem(MconnCryptPrivate *priv)
{
    gchar *pubkey = NULL;

    /* memory IO  */
    BIO *bm = BIO_new(BIO_s_mem());

    /* generate PEM */
    /* PEM_write_bio_RSAPublicKey(bm, priv->key); */
    PEM_write_bio_RSA_PUBKEY(bm, priv->key);

    /* get PEM as text */
    char *oss_pubkey = NULL;
    long data = BIO_get_mem_data(bm, &oss_pubkey);
    g_debug("mconn-crypt: public key length: %ld", data);
    g_assert(data != 0);
    g_assert(oss_pubkey != NULL);

    /* dup the key as buffer goes away with BIO */
    pubkey = g_strndup(oss_pubkey, data);

    BIO_set_close(bm, BIO_CLOSE);
    BIO_free(bm);

    return pubkey;
}

static gchar *__mconn_get_uuid(MconnCryptPrivate *priv)
{
    gchar *uuid = NULL;
    
    X509_NAME *name;
    if (!(name = X509_get_subject_name(priv->cert)))
    {
        g_critical("mconn-crypt: failed to retrieve subject name from certificate");
        return uuid;
    }

    int common_name_loc = -1;
    X509_NAME_ENTRY *common_name_entry = NULL;
    ASN1_STRING *common_name_asn1 = NULL;
    char *common_name_str = NULL;

    // Find the position of the CN field in the Subject field of the certificate
    common_name_loc = X509_NAME_get_index_by_NID(name, NID_commonName, -1);
    if (common_name_loc < 0)
    {
        g_critical("mconn-crypt: failed to retrieve uuid from certificate");
        return uuid;
    }

    // Extract the CN field
    common_name_entry = X509_NAME_get_entry(name, common_name_loc);
    if (common_name_entry == NULL)
    {
        g_critical("mconn-crypt: failed to retrieve uuid from certificate");
        return uuid;
    }

    // Convert the CN field to a C string
    common_name_asn1 = X509_NAME_ENTRY_get_data(common_name_entry);
    if (common_name_asn1 == NULL)
    {
        g_critical("mconn-crypt: failed to retrieve uuid from certificate");
        return uuid;
    }
    common_name_str = (char *) ASN1_STRING_get0_data(common_name_asn1);

    // Make sure there isn't an embedded NUL character in the CN
    if ((size_t)ASN1_STRING_length(common_name_asn1) != strlen(common_name_str))
    {
        g_critical("mconn-crypt: failed to retrieve uuid from certificate, length not conform");
        return uuid;
    }

    /* dup the key as buffer goes away with BIO */
    uuid = g_strndup(common_name_str, 37);
    return uuid;
}

static gboolean __mconn_load_key(MconnCryptPrivate *priv, const char *path)
{
    if (g_file_test(path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_critical("mconn-crypt: key file %s does not exist", path);
        return FALSE;
    }

    g_debug("mconn-crypt: loading key from %s", path);

    BIO *bf = BIO_new_file(path, "r");

    if (bf == NULL)
    {
        g_critical("mconn-crypt: failed to open file %s", path);
        return FALSE;
    }

    RSA *rsa = NULL;

    rsa = PEM_read_bio_RSAPrivateKey(bf, NULL, NULL, NULL);

    BIO_free(bf);

    if (rsa == NULL)
    {
        g_critical("mconn-crypt: failed to read private key");
        return FALSE;
    }

    priv->key = rsa;

    return TRUE;
}

static gboolean __mconn_load_cert(MconnCryptPrivate *priv, const char *path)
{
    if (g_file_test(path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_critical("mconn-crypt: certificate file %s does not exist", path);
        return FALSE;
    }

    g_debug("mconn-crypt: loading certificate from %s", path);

    BIO *bf = BIO_new_file(path, "r");

    if (bf == NULL)
    {
        g_critical("mconn-crypt: failed to open file %s", path);
        return FALSE;
    }

    X509 *cert = NULL;

    cert = PEM_read_bio_X509(bf, NULL, 0, NULL);

    BIO_free(bf);

    if (cert == NULL)
    {
        g_critical("mconn-crypt: failed to read certificate");
        return FALSE;
    }

    priv->cert = cert;

    return TRUE;
}

static gboolean __mconn_generate_key_at_path(const char *path)
{
    gboolean ret = TRUE;
    RSA *rsa = NULL;
    BIGNUM *bn = NULL;
    int bits = 2048;

    BIO *bf = BIO_new_file(path, "w");
    if (bf == NULL)
    {
        g_error("mconn-crypt: failed to open file");
        return FALSE;
    }

    // Generate RSA private key
    bn = BN_new();
    BN_set_word(bn, RSA_F4);

    rsa = RSA_new();
    if (!RSA_generate_key_ex(rsa, bits, bn, NULL)) return ret;

    /* the big number is no longer used */
    BN_free(bn);

    if (PEM_write_bio_RSAPrivateKey(bf, rsa, NULL, NULL, 0, NULL, NULL) == 0)
    {
        g_critical("mconn-crypt: failed to private write key to file");
        ret = FALSE;
    }

    RSA_free(rsa);

    BIO_free(bf);

    return ret;
}

static int __mconn_certificate_add_ext(X509 *cert, int nid, char *value)
{
	X509_EXTENSION *ex;
	X509V3_CTX ctx;
	/* This sets the 'context' of the extensions. */
	/* No configuration database */
	X509V3_set_ctx_nodb(&ctx);
	/* Issuer and subject certs: both the target since it is self signed,
	 * no request and no CRL
	 */
	X509V3_set_ctx(&ctx, cert, cert, NULL, NULL, 0);
	ex = X509V3_EXT_conf_nid(NULL, &ctx, nid, value);
	if (!ex)
		return 0;

	X509_add_ext(cert,ex,-1);
	X509_EXTENSION_free(ex);
	return 1;
}

static gboolean __mconn_generate_certificate_at_path(const char *key_path, const char *cert_path,
                const char *OrganizationName, const char *OrganizationUnit, int YearsValid)
{
    gboolean ret = FALSE;

    X509 *cert = NULL;
    RSA *rsa = NULL;
    EVP_PKEY *pk = NULL;
    X509_NAME *name = NULL;

    BIO *bf = NULL;

    // Assign a public key
    if (g_file_test(key_path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_critical("mconn-crypt: key file %s does not exist", key_path);
        return ret;
    }

    bf = BIO_new_file(key_path, "r");
    if (bf == NULL)
    {
        g_critical("mconn-crypt: failed to open file %s", key_path);
        return ret;
    }

    if (!(pk=PEM_read_bio_PrivateKey(bf, NULL, NULL, NULL)))
    {
        g_critical("mconn-crypt: failed to assign public key");
        return ret;
    }

    if (!(cert = X509_new()))
    {
        g_critical("mconn-crypt: failed to create new certificate");
        return ret;
    }
    X509_set_version(cert, 0x2); // version 3

    ASN1_INTEGER_set(X509_get_serialNumber(cert), 1);  // Serial number of 0 is sometimes refused
    X509_gmtime_adj(X509_get_notBefore(cert), 0);
    X509_gmtime_adj(X509_get_notAfter(cert), (long)60*60*24*365*YearsValid);
   
    X509_set_pubkey(cert, pk);

    name = X509_get_subject_name(cert);
   
    /* This function creates and adds the entry, working out the
    * correct string type and performing checks on its length.
    * Normally we'd check the return value for errors...
    */
    if (OrganizationName && *OrganizationName) 
    {
        X509_NAME_add_entry_by_txt(name, "O", MBSTRING_ASC, (unsigned char *)OrganizationName, -1, -1, 0);
    }
    if (OrganizationUnit && *OrganizationUnit) 
    {
        X509_NAME_add_entry_by_txt(name, "OU", MBSTRING_ASC, (unsigned char *)OrganizationUnit, -1, -1, 0);
    }

    /* Generate uuid */
    uuid_t uuid_int;
    uuid_generate(uuid_int);
    char uuid[37];      // ex. "1b4e28ba-2fa1-11d2-883f-0016d3cca427" + "\0"
    uuid_unparse_lower(uuid_int, uuid);
    // test for valid arguments
    if (!uuid || *uuid == 0)
    {
        g_critical("mconn-crypt: uuid not defined");
        return ret;
    }
    g_debug("mconn-crypt: generated uuid %s", uuid);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, (unsigned char *)uuid, -1, -1, 0);

    /* Set issuer and subject */
    X509_set_issuer_name(cert, name);
    X509_set_subject_name(cert, name);
    
	/* Add various extensions: standard extensions */
	__mconn_certificate_add_ext(cert, NID_basic_constraints, "critical,CA:TRUE");
	//__mconn_certificate_add_ext(cert, NID_key_usage, "critical,keyCertSign,cRLSign");
	__mconn_certificate_add_ext(cert, NID_subject_key_identifier, "hash");
	__mconn_certificate_add_ext(cert, NID_authority_key_identifier, "keyid:always");


    if (!X509_sign(cert, pk, EVP_sha256()))
    {
        g_critical("mconn-crypt: failed to sign certificate");
        return ret;
    }

    // Copy private key and certificate to file
    bf = BIO_new_file(cert_path, "w");
    if (bf == NULL)
    {
        g_error("mconn-crypt: failed to open cert file");
        return FALSE;
    }

    if (PEM_write_bio_X509(bf, cert) == 0)
    {
        g_critical("mconn-crypt: failed to write certificate to file");
        ret = FALSE;
    }

    BIO_free(bf);
    EVP_PKEY_free(pk);
    X509_free(cert);

    return (TRUE);
}
