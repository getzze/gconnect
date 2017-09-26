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
#include <gnutls/gnutls.h>
//#include <gnutls/extra.h>
#include <gnutls/x509.h>

#include <string.h>
#include <stdio.h>
#include <time.h>
#include <sys/stat.h>
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>

#include "crypt.h"

typedef struct _GconnectCryptCryptPrivate      GconnectCryptCryptPrivate;

/**
 * GconnectCryptCrypt:
 *
 * A simple wrapper for crypto operations.
 **/

struct _GconnectCryptCrypt
{
    GObject parent;
    GconnectCryptCryptPrivate *priv;
};

struct _GconnectCryptCryptPrivate
{
    char                     uuid[37];          /* UUID for certificate CommonName */
    gnutls_x509_privkey_t    *key;           /* RSA key wrapper */
    gnutls_x509_crt_t        *cert;          /* Certificate wrapper */
};

static void gconnect_crypt_crypt_dispose (GObject *object);
static void gconnect_crypt_crypt_finalize (GObject *object);

static gboolean __gconnect_crypt_load_key(GconnectCryptCryptPrivate *priv, const char *path);
static gboolean __gconnect_crypt_load_cert(GconnectCryptCryptPrivate *priv, const char *path);
static gboolean __gconnect_crypt_generate_key_at_path(const char *path);
static gboolean __gconnect_crypt_generate_certificate_at_path(const gnutls_x509_privkey_t *key, const char *cert_path,
                const char *CommonName, const char *OrganizationName, const char *OrganizationUnit, int YearsValid);
static gboolean __gconnect_crypt_append_extension(gnutls_x509_crt_t *crt);

G_DEFINE_TYPE_WITH_PRIVATE (GconnectCryptCrypt, gconnect_crypt_crypt, G_TYPE_OBJECT);

static void
gconnect_crypt_crypt_class_init (GconnectCryptCryptClass *klass)
{
    GObjectClass *gobject_class = (GObjectClass *)klass;

    gobject_class->dispose = gconnect_crypt_crypt_dispose;
    gobject_class->finalize = gconnect_crypt_crypt_finalize;
}

static void
gconnect_crypt_crypt_init (GconnectCryptCrypt *self)
{
    g_debug("crypt: new instance");
    self->priv = gconnect_crypt_crypt_get_instance_private(self);
}

static void
gconnect_crypt_crypt_dispose (GObject *object)
{
    GconnectCryptCrypt *self = (GconnectCryptCrypt *)object;

    if (self->priv->key != NULL)
    {
        gnutls_x509_privkey_deinit(self->priv->key);
        self->priv->key = NULL;
    }

    if (self->priv->cert != NULL)
    {
        gnutls_x509_crt_deinit(self->priv->cert);
        self->priv->cert = NULL;
    }

    G_OBJECT_CLASS (gconnect_crypt_crypt_parent_class)->dispose (object);
}

static void
gconnect_crypt_crypt_finalize (GObject *object)
{
    GconnectCryptCrypt *self = (GconnectCryptCrypt *)object;

    g_signal_handlers_destroy (object);
    G_OBJECT_CLASS (gconnect_crypt_crypt_parent_class)->finalize (object);
}

GconnectCryptCrypt *gconnect_crypt_crypt_new_for_key_path(const char *path)
{

    GconnectCryptCrypt *self = g_object_new(GCONNECT_CRYPT_TYPE_CRYPT, NULL);

    if (g_file_test(path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_debug("crypt: generate new private key at path %s", path);
        __gconnect_crypt_generate_key_at_path(path);
    }

    if (__gconnect_crypt_load_key(self->priv, path) == FALSE)
    {
        gconnect_crypt_crypt_unref(self);
        return NULL;
    }

    return self;
}

GconnectCryptCrypt *gconnect_crypt_crypt_new(const char *key_path, const char *cert_path, const char *uuid)
{
    GconnectCryptCrypt *self = gconnect_crypt_crypt_new_for_key_path(key_path);
    g_assert(self);

    
    g_assert(self->priv);
    g_assert(self->priv->key);

    strcpy(self->priv->uuid, uuid);
    g_assert(self->priv->uuid);
        
    if (g_file_test(cert_path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_debug("crypt: generate new certificate at path %s", cert_path);
        __gconnect_crypt_generate_certificate_at_path(self->priv->key, cert_path, self->priv->uuid, "KDE", "KDE Connect", 10);
    }

    if (__gconnect_crypt_load_cert(self->priv, cert_path) == FALSE)
    {
        gconnect_crypt_crypt_unref(self);
        return NULL;
    }

    return self;
}

GconnectCryptCrypt * gconnect_crypt_crypt_ref(GconnectCryptCrypt *self)
{
    g_assert(IS_GCONNECT_CRYPT_CRYPT(self));
    return GCONNECT_CRYPT_CRYPT(g_object_ref(self));
}

void gconnect_crypt_crypt_unref(GconnectCryptCrypt *self)
{
    if (self != NULL)
    {
        g_assert(IS_GCONNECT_CRYPT_CRYPT(self));
        g_object_unref(self);
    }
}


/**
 *
 */
static char *fread_file (FILE * stream, size_t * length)
{
  char *buf = NULL;
  size_t alloc = 0;

  /* For a regular file, allocate a buffer that has exactly the right
     size.  This avoids the need to do dynamic reallocations later.  */
  {
    struct stat st;

    if (fstat (fileno (stream), &st) >= 0 && S_ISREG (st.st_mode))
      {
        off_t pos = ftello (stream);

        if (pos >= 0 && pos < st.st_size)
          {
            off_t alloc_off = st.st_size - pos;

            if (SIZE_MAX <= alloc_off)
              {
                errno = ENOMEM;
                return NULL;
              }

            alloc = alloc_off + 1;

            buf = malloc (alloc);
            if (!buf)
              /* errno is ENOMEM.  */
              return NULL;
          }
      }
  }

  {
    size_t size = 0; /* number of bytes read so far */
    int save_errno;

    for (;;)
      {
        size_t count;
        size_t requested;

        if (size + BUFSIZ + 1 > alloc)
          {
            char *new_buf;
            size_t new_alloc = alloc + alloc / 2;

            /* Check against overflow.  */
            if (new_alloc < alloc)
              {
                save_errno = ENOMEM;
                break;
              }

            alloc = new_alloc;
            if (alloc < size + BUFSIZ + 1)
              alloc = size + BUFSIZ + 1;

            new_buf = realloc (buf, alloc);
            if (!new_buf)
              {
                save_errno = errno;
                break;
              }

            buf = new_buf;
          }

        requested = alloc - size - 1;
        count = fread (buf + size, 1, requested, stream);
        size += count;

        if (count != requested)
          {
            save_errno = errno;
            if (ferror (stream))
              break;

            /* Shrink the allocated memory if possible.  */
            if (size + 1 < alloc)
              {
                char *smaller_buf = realloc (buf, size + 1);
                if (smaller_buf != NULL)
                  buf = smaller_buf;
              }

            buf[size] = '\0';
            *length = size;
            return buf;
          }
      }

    free (buf);
    errno = save_errno;
    return NULL;
  }
}

static gboolean __gconnect_crypt_load_key(GconnectCryptCryptPrivate *priv, const char *path)
{
    gnutls_x509_privkey_t key;
    size_t size;
    int res = 0;
    gnutls_datum_t pem;
    FILE *infile;

    if (g_file_test(path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_critical("crypt: key file %s does not exist", path);
        return FALSE;
    }

    g_debug("crypt: loading key from %s", path);

    infile = fopen(path, "rb");
    if (infile == NULL)
    {
        g_critical("crypt: failed to open file %s", path);
        return FALSE;
    }

    pem.data = fread_file (infile, &size);
    pem.size = size;

    fclose( infile );
    gnutls_x509_privkey_init(&key);


    res = gnutls_x509_privkey_import (key, &pem, GNUTLS_X509_FMT_PEM);
    if (res < 0)
    {
        g_critical("crypt: import error: %s", gnutls_strerror(res));
        return FALSE;
    }

    priv->key = &key;

    free(pem.data);
    return TRUE;
}

static gboolean __gconnect_crypt_load_cert(GconnectCryptCryptPrivate *priv, const char *path)
{
    gnutls_x509_crt_t cert;
    size_t size;
    int res = 0;
    gnutls_datum_t pem;
    FILE *infile;

    if (g_file_test(path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_critical("crypt: cert file %s does not exist", path);
        return FALSE;
    }

    g_debug("crypt: loading cert from %s", path);

    infile = fopen(path, "rb");
    if (infile == NULL)
    {
        g_critical("crypt: failed to open file %s", path);
        return FALSE;
    }

    pem.data = fread_file (infile, &size);
    pem.size = size;

    fclose( infile );
    gnutls_x509_crt_init (&cert);

    res = gnutls_x509_crt_import (cert, &pem, GNUTLS_X509_FMT_PEM);
    if (res < 0)
    {
        g_critical("crypt: import error: %s", gnutls_strerror(res));
        return FALSE;
    }

    priv->cert = &cert;

    free(pem.data);
    return TRUE;
}

static gboolean __gconnect_crypt_generate_key_at_path(const char *path)
{
    gnutls_x509_privkey_t *key;
    int res, key_type, bits;
    size_t size;
    unsigned char buffer[64 * 1024];
    const int buffer_size = sizeof (buffer);
    FILE *outfile;
   
    key_type = GNUTLS_PK_RSA;
    bits = 2048;
   
    res = gnutls_x509_privkey_init (key);
    if (res < 0)
    {
        g_critical("crypt: cannot initiate private key: %s", gnutls_strerror (res));
        return FALSE;
    }

    res = gnutls_x509_privkey_generate(*key, key_type, bits, 0);
    if (res < 0 || !key)
    {
        g_critical("crypt: cannot generate private key: %s", gnutls_strerror (res));
        gnutls_x509_privkey_deinit(*key);
        return FALSE;
    }

    size = buffer_size;
    res = gnutls_x509_privkey_export (*key, GNUTLS_X509_FMT_PEM, buffer, &size);
    gnutls_x509_privkey_deinit(*key);
    if (res < 0)
    {
        g_critical("crypt: cannot export private key: %s", gnutls_strerror (res));
        return FALSE;
    }

    outfile = fopen(path, "wb");
    if (outfile == NULL)
    {
        g_critical("crypt: failed to open file %s", path);
        return FALSE;
    }
    fwrite (buffer, 1, size, outfile);
    fclose( outfile );

    return TRUE;
}

static gboolean __gconnect_crypt_append_extension (gnutls_x509_crt_t *crt)
{
    /* append additional extensions */
    int client, ca_status = 0, is_ike = 0, signing_key = 0;
    unsigned int usage = 0, server;

    ca_status = 1;
    client = 1;
    server = 1;
    is_ike = 0;
    signing_key = 0;
    

    gnutls_x509_crt_set_basic_constraints (*crt, ca_status, -1);
    if (client)
    {
        gnutls_x509_crt_set_key_purpose_oid (*crt, GNUTLS_KP_TLS_WWW_CLIENT, 0);
    }

    if ( server != 0 || is_ike)
      {
        //get_dns_name_set (TYPE_CRT, crt);
        //get_ip_addr_set (TYPE_CRT, crt);
      }

    if (server != 0)
    {
        gnutls_x509_crt_set_key_purpose_oid (*crt, GNUTLS_KP_TLS_WWW_SERVER, 0);
    }

    if (!ca_status || server)
      {
        int encryption_key = 0;

        if (signing_key)
            usage |= GNUTLS_KEY_DIGITAL_SIGNATURE;

        if (encryption_key)
            usage |= GNUTLS_KEY_KEY_ENCIPHERMENT;

        if (is_ike)
          {
            gnutls_x509_crt_set_key_purpose_oid (*crt, GNUTLS_KP_IPSEC_IKE, 0);
          }
      }


    if (ca_status)
    {
        int cert_signing_key = 0;
        int crl_signing_key = 0;
        int code_signing_key = 0;
        int ocsp_signing_key = 0;
        int time_stamping_key = 0;

        if (cert_signing_key)
            usage |= GNUTLS_KEY_KEY_CERT_SIGN;

        if (crl_signing_key)
            usage |= GNUTLS_KEY_CRL_SIGN;

        if (code_signing_key)
        {
            gnutls_x509_crt_set_key_purpose_oid (*crt, GNUTLS_KP_CODE_SIGNING, 0);
        }

        if (ocsp_signing_key)
        {
            gnutls_x509_crt_set_key_purpose_oid (*crt, GNUTLS_KP_OCSP_SIGNING, 0);
        }

        if (time_stamping_key)
        {
            gnutls_x509_crt_set_key_purpose_oid (crt, GNUTLS_KP_TIME_STAMPING, 0);
        }
    }

    if (usage != 0)
    {
        /* http://tools.ietf.org/html/rfc4945#section-5.1.3.2: if any KU is
           set, then either digitalSignature or the nonRepudiation bits in the
           KeyUsage extension MUST for all IKE certs */
        if (is_ike && (signing_key != 1))
            usage |= GNUTLS_KEY_NON_REPUDIATION;
        gnutls_x509_crt_set_key_usage (*crt, usage);
    }
}

static gboolean __gconnect_crypt_generate_certificate_at_path(const gnutls_x509_privkey_t *key, const char *path,
                const char *CommonName, const char *OrganizationName, const char *OrganizationUnit, int YearsValid)
{
    gnutls_x509_crt_t crt;
    size_t size;
    int res;
    unsigned char buffer[64 * 1024];
    const int buffer_size = sizeof (buffer);
    FILE *outfile;

    res = gnutls_x509_crt_init (&crt);
    if (res < 0)
    {
        g_critical("crypt: cannot initialize certificate: %s", gnutls_strerror (res));
        return FALSE;
    }
   
    res = gnutls_x509_crt_set_version (crt, 3);
    if (res < 0)
    {
        g_critical("crypt: cannot set certificate version: %s", gnutls_strerror (res));
        return FALSE;
    }

    gnutls_x509_crt_set_dn_by_oid (crt, GNUTLS_OID_X520_COMMON_NAME, 0, CommonName, strlen(CommonName));
    gnutls_x509_crt_set_dn_by_oid (crt, GNUTLS_OID_X520_ORGANIZATION_NAME, 0, OrganizationName, strlen(OrganizationName));
    gnutls_x509_crt_set_dn_by_oid (crt, GNUTLS_OID_X520_ORGANIZATIONAL_UNIT_NAME, 0, OrganizationUnit, strlen(OrganizationUnit));
    {
        char bin_serial[1];
        bin_serial[0] = 0x02;
        res = gnutls_x509_crt_set_serial (crt, bin_serial, 1);
        if (res < 0)
        {
            g_critical("crypt: cannot set certificate serial: %s", gnutls_strerror (res));
            return FALSE;
        }
    }

    time_t now = time (NULL);
    gnutls_x509_crt_set_activation_time (crt, now);
    gnutls_x509_crt_set_expiration_time (crt, now + YearsValid * 365 * 24 * 60 * 60);

    g_debug("crypt: assign private key to certificate");
    res = gnutls_x509_crt_set_key(crt, *key);
    if (res < 0)
    {
        g_critical("crypt: cannot set certificate private key: %s", gnutls_strerror (res));
        return FALSE;
    }

    /* Subject Key ID.
     */
    size = buffer_size;
    res = gnutls_x509_crt_get_key_id (crt, 0, buffer, &size);
    if (res >= 0)
    {
        res = gnutls_x509_crt_set_subject_key_id (crt, buffer, size);
        if (res < 0)
        {
            g_critical("crypt: cannot set subject key id: %s", gnutls_strerror (res));
            return FALSE;
        }
    }

    gnutls_x509_crt_set_key_purpose_oid (crt, GNUTLS_KP_TLS_WWW_CLIENT, 0);
    gnutls_x509_crt_set_key_purpose_oid (crt, GNUTLS_KP_TLS_WWW_SERVER, 0);

    gnutls_x509_crt_set_basic_constraints (crt, 1, -1);  // CA authority


    // Signing certificate
    g_debug("crypt: signing certificate");
  
    res = gnutls_x509_crt_sign2 (crt, crt, *key, GNUTLS_DIG_SHA256, 0);
    if (res < 0)
    {
        g_critical("crypt: error signing certificate: %s", gnutls_strerror (res));
        return FALSE;
    }
    
    size = buffer_size;
    res = gnutls_x509_crt_export (crt, GNUTLS_X509_FMT_PEM, buffer, &size);
    gnutls_x509_crt_deinit(crt);
    if (res < 0)
    {
        g_critical("crypt: cannot export certificate: %s", gnutls_strerror (res));
        return FALSE;
    }
  
    outfile = fopen(path, "wb");
    if (outfile == NULL)
    {
        g_critical("crypt: failed to open file %s", path);
        return FALSE;
    }
    fwrite (buffer, 1, size, outfile);
    fclose( outfile );

    return TRUE;
}
