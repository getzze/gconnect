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

#ifndef __GCONNECT_CRYPT_H__
#define __GCONNECT_CRYPT_H__

#include <glib-object.h>
#include <glib.h>
#include <glib/gbytes.h>

#include <gnutls/gnutls.h>
#include <gnutls/x509.h>

G_BEGIN_DECLS

gnutls_x509_privkey_t gconnect_crypt_import_private_key_from_pem_file(const char *path);
gnutls_x509_crt_t gconnect_crypt_import_certificate_from_pem_file(const char *path);
gboolean gconnect_crypt_export_private_key_to_pem_file(const gnutls_x509_privkey_t *key, const char *path);
gboolean gconnect_crypt_export_certificate_to_pem_file(const gnutls_x509_crt_t *crt, const char *path);
gnutls_x509_crt_t gconnect_crypt_certificate_create(const gnutls_x509_privkey_t *key, guchar serial);

G_END_DECLS

#endif /* __GCONNECT_CRYPT_H__ */
