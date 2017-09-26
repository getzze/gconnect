
/* ex:ts=4:sw=4:sts=4:et */
/* -*- tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*- */
/*
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
 * Author: Maciek Borzecki <maciek.borzecki (at] gmail.com>
 */
#ifndef __GCONNECT_CRYPT_H__
#define __GCONNECT_CRYPT_H__

#include <glib-object.h>
#include <glib.h>
#include <glib/gbytes.h>

G_BEGIN_DECLS

#define GCONNECT_CRYPT_TYPE_CRYPT                        \
   (gconnect_crypt_crypt_get_type())
#define GCONNECT_CRYPT_CRYPT(obj)                                                \
   (G_TYPE_CHECK_INSTANCE_CAST ((obj),                                  \
                                GCONNECT_CRYPT_TYPE_CRYPT,                       \
                                GconnectCryptCrypt))
#define GCONNECT_CRYPT_CRYPT_CLASS(klass)                                        \
   (G_TYPE_CHECK_CLASS_CAST ((klass),                                   \
                             GCONNECT_CRYPT_TYPE_CRYPT,                          \
                             GconnectCryptCrypt))
#define IS_GCONNECT_CRYPT_CRYPT(obj)                                             \
   (G_TYPE_CHECK_INSTANCE_TYPE ((obj),                                  \
                                GCONNECT_CRYPT_TYPE_CRYPT))
#define IS_GCONNECT_CRYPT_CRYPT_CLASS(klass)                                     \
   (G_TYPE_CHECK_CLASS_TYPE ((klass),                                   \
                             GCONNECT_CRYPT_TYPE_CRYPT))
#define GCONNECT_CRYPT_CRYPT_GET_CLASS(obj)                                      \
   (G_TYPE_INSTANCE_GET_CLASS ((obj),                                   \
                               GCONNECT_CRYPT_TYPE_CRYPT,                        \
                               GconnectCryptCryptClass))

typedef struct _GconnectCryptCrypt      GconnectCryptCrypt;
typedef struct _GconnectCryptCryptClass GconnectCryptCryptClass;
struct _GconnectCryptCryptClass
{
    GObjectClass parent_class;
};

GType gconnect_crypt_crypt_get_type (void) G_GNUC_CONST;

/**
 * mconn_crypt_new_for_key_path: (constructor)
 * @path: key path
 *
 * Returns: (transfer full): new object
 */
GconnectCryptCrypt *gconnect_crypt_crypt_new_for_key_path(const char *path);

/**
 * gconnect_crypt_crypt_new: (constructor)
 * @key_path: private key path
 * @cert_path: certificate path
 *
 * Returns: (transfer full): new object
 */
GconnectCryptCrypt *gconnect_crypt_crypt_new(const char *key_path, const char *cert_path, const char *uuid);

/**
 * gconnect_crypt_crypt_unref:
 * @crypt: crypt object
 */
void gconnect_crypt_crypt_unref(GconnectCryptCrypt *crypt);

/**
 * gconnect_crypt_crypt_ref:
 * @crypt: crypt object
 *
 * Take reference to crypt object
 * Returns: (transfer none): reffed object
 */
GconnectCryptCrypt *gconnect_crypt_crypt_ref(GconnectCryptCrypt *crypt);

G_END_DECLS

#endif /* __GCONNECT_CRYPT_H__ */
