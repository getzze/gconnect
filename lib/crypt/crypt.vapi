namespace Gconnect.Crypt {
	[CCode (cheader_filename = "crypt.h", type_id = "gconnect_crypt_crypt_get_type ()")]
	public class Crypt : GLib.Object {
		[CCode (has_construct_function = false)]
		public Crypt (string key_path, string cert_path, string uuid);
		public unowned Crypt @ref ();
		public void unref ();
	}
}

