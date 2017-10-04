/* xtst.vapi
 *
 * Copyright (C) 2012  Alexander Kurtz
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Alexander Kurtz <kurtz.alex@googlemail.com>
 */

[CCode (cprefix = "XTest", cheader_filename = "X11/extensions/XTest.h")]
namespace XTest {
	[CCode (cname = "XTestQueryExtension")]
	public static bool query_extension (X.Display display, out int event_base_return, out int error_base_return, out int major_version_return, out int minor_version_return);

	[CCode (cname = "XTestCompareCursorWithWindow")]
	public static bool compare_cursor_with_window (X.Display display, X.Window window, X.Cursor cursor);

	[CCode (cname = "XTestCompareCurrentCursorWithWindow")]
	public static bool compare_current_cursor_with_window (X.Display display, X.Window window);

	[CCode (cname = "XTestFakeKeyEvent")]
	public static int fake_key_event (X.Display display, uint keycode, bool is_press, ulong delay);

	[CCode (cname = "XTestFakeButtonEvent")]
	public static int fake_button_event (X.Display display, uint button, bool is_press, ulong delay);

	[CCode (cname = "XTestFakeMotionEvent")]
	public static int fake_motion_event (X.Display display, int screen_number, int x, int y, ulong delay);

	[CCode (cname = "XTestFakeRelativeMotionEvent")]
	public static int fake_relative_motion_event (X.Display display, int x, int y, ulong delay);

	[CCode (cname = "XTestGrabControl")]
	public static int grab_control (X.Display display, bool impervious);

	[CCode (cname = "XTestSetGContextOfGC")]
	public static void set_g_context_of_gc (X.GC gc, X.GContext gid);

	[CCode (cname = "XTestSetVisualIDOfVisual")]
	public static void set_visual_id_of_visual (X.Visual visual, X.VisualID visualid);

	[CCode (cname = "XTestDiscard")]
	public static X.Status discard (X.Display display);
}
