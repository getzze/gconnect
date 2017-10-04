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
 
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>

#include "crypt.h"


static char *fread_file (FILE * stream, size_t * length);

gnutls_x509_privkey_t gconnect_crypt_import_private_key_from_pem_file(const char *path)
{
    gnutls_x509_privkey_t key;
    size_t size;
    int res = 0;
    gnutls_datum_t pem;
    FILE *infile;

    if (g_file_test(path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_critical("crypt: key file %s does not exist", path);
        return NULL;
    }

    g_debug("crypt: loading key from %s", path);

    infile = fopen(path, "rb");
    if (infile == NULL)
    {
        g_critical("crypt: failed to open file %s", path);
        return NULL;
    }

    pem.data = fread_file (infile, &size);
    pem.size = size;

    fclose( infile );
    gnutls_x509_privkey_init(&key);


    res = gnutls_x509_privkey_import (key, &pem, GNUTLS_X509_FMT_PEM);
    if (res < 0)
    {
        g_critical("crypt: import error: %s", gnutls_strerror(res));
        return NULL;
    }
    free(pem.data);
    return key;
}

gnutls_x509_crt_t gconnect_crypt_import_certificate_from_pem_file(const char *path)
{
    gnutls_x509_crt_t cert;
    size_t size;
    int res = 0;
    gnutls_datum_t pem;
    FILE *infile;

    if (g_file_test(path, G_FILE_TEST_EXISTS) == FALSE)
    {
        g_critical("crypt: cert file %s does not exist", path);
        return NULL;
    }

    g_debug("crypt: loading cert from %s", path);

    infile = fopen(path, "rb");
    if (infile == NULL)
    {
        g_critical("crypt: failed to open file %s", path);
        return NULL;
    }

    pem.data = fread_file (infile, &size);
    pem.size = size;

    fclose( infile );
    gnutls_x509_crt_init (&cert);

    res = gnutls_x509_crt_import (cert, &pem, GNUTLS_X509_FMT_PEM);
    if (res < 0)
    {
        g_critical("crypt: import error: %s", gnutls_strerror(res));
        return NULL;
    }

    free(pem.data);
    return cert;
}

gboolean gconnect_crypt_export_private_key_to_pem_file(const gnutls_x509_privkey_t *key, const char *path)
{
    int res;
    size_t size;
    unsigned char buffer[64 * 1024];
    const int buffer_size = sizeof (buffer);
    FILE *outfile;

    g_assert(key);
    size = buffer_size;
    res = gnutls_x509_privkey_export (key, GNUTLS_X509_FMT_PEM, buffer, &size);
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

gboolean gconnect_crypt_export_certificate_to_pem_file(const gnutls_x509_crt_t *crt, const char *path)
{
    int res;
    size_t size;
    unsigned char buffer[64 * 1024];
    const int buffer_size = sizeof (buffer);
    FILE *outfile;

    g_assert(crt);
    size = buffer_size;
    res = gnutls_x509_crt_export (crt, GNUTLS_X509_FMT_PEM, buffer, &size);
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

gnutls_x509_crt_t gconnect_crypt_certificate_create(const gnutls_x509_privkey_t *key, guchar serial)
{
    gnutls_x509_crt_t crt;
    size_t size;
    int res;
    unsigned char buffer[64 * 1024];
    const int buffer_size = sizeof (buffer);

    gnutls_x509_crt_init (&crt);

    // Version v3
    res = gnutls_x509_crt_set_version (crt, 3);
    if (res < 0)
    {
        g_critical("crypt: cannot set certificate version: %s", gnutls_strerror (res));
        return FALSE;
    }

    // Serial
    {
        guchar bin_serial[1];
        bin_serial[0] = serial;
        res = gnutls_x509_crt_set_serial (crt, bin_serial, 1);
        if (res < 0)
        {
            g_critical("crypt: cannot set certificate serial: %s", gnutls_strerror (res));
            return NULL;
        }
    }
    
    g_debug("crypt: assign private key to certificate");
    res = gnutls_x509_crt_set_key(crt, key);
    if (res < 0)
    {
        g_critical("crypt: cannot set certificate private key: %s", gnutls_strerror (res));
        return NULL;
    }

    // Subject Key ID.
    size = buffer_size;
    res = gnutls_x509_crt_get_key_id (crt, 0, buffer, &size);
    if (res >= 0)
    {
        res = gnutls_x509_crt_set_subject_key_id (crt, buffer, size);
        if (res < 0)
        {
            g_critical("crypt: cannot set subject key id: %s", gnutls_strerror (res));
            return NULL;
        }
    }
    return crt;
}


/**
 *  Copied directly from GnuTLS code
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
