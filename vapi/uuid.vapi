/* guuid Vala Bindings
 */

[CCode (cheader_filename = "glib/guuid.h", lower_case_cprefix = "g_uuid_string_")]
namespace Guuid {
	public string random ();
	public bool is_valid (string str);
}
