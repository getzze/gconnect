/**
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
 *
 * Bertrand Lacoste <getzze [at) gmail.com>
 * Using c code from yoctoproject fakekey:
 * http://git.yoctoproject.org/cgit/cgit.cgi/libfakekey/tree/
 */


using Gdk;
//using XTest;

// Use a different namespace for each plugin to avoid using the same class names
namespace PluginsGconnect.Mousepad {

	public class Fakekey : GLib.Object {
        private unowned X.Display xdisplay = null;

        private int min_keycode;
        private int max_keycode;
        private int n_keysyms_per_keycode;
        private ulong[] keysyms;
        private uchar held_keycode;
        private Gdk.ModifierType held_state_flags;
        
        private int modified_key;
        
		public Fakekey (X.Display display) {
            this.xdisplay = display;
            
            this.xdisplay.keycodes(ref this.min_keycode, ref this.max_keycode);
            this.keysyms = this.xdisplay.get_keyboard_mapping((uchar)this.min_keycode,
                                                             this.max_keycode - this.min_keycode + 1,
                                                             ref this.n_keysyms_per_keycode);
        }
        
        private void send_keyevent(uchar keycode, bool is_press, Gdk.ModifierType flags) {
            if (is_press) {  // Modifiers first
                send_modifiersevent(flags, is_press);
                XTest.fake_key_event(this.xdisplay, keycode, is_press, 0);
            } else {
                XTest.fake_key_event(this.xdisplay, keycode, is_press, 0);
                send_modifiersevent(flags, is_press);
            }
        }

        private void send_modifiersevent(Gdk.ModifierType flags, bool is_press) {
            if (Gdk.ModifierType.SHIFT_MASK in flags) {
                XTest.fake_key_event(this.xdisplay, this.xdisplay.keysym_to_keycode(Gdk.Key.Shift_L), is_press, 0);
            }
            if (Gdk.ModifierType.CONTROL_MASK in flags) {
                XTest.fake_key_event(this.xdisplay, this.xdisplay.keysym_to_keycode(Gdk.Key.Control_L), is_press, 0);
            }
            if (Gdk.ModifierType.MOD1_MASK in flags) {  // Alt key
                XTest.fake_key_event(this.xdisplay, this.xdisplay.keysym_to_keycode(Gdk.Key.Alt_L), is_press, 0);
            }
            if (Gdk.ModifierType.META_MASK in flags) {  // Meta key
                XTest.fake_key_event(this.xdisplay, this.xdisplay.keysym_to_keycode(Gdk.Key.Meta_L), is_press, 0);
            }
        }

        public bool press (ulong keysym, Gdk.ModifierType flags) {
            var code = this.xdisplay.keysym_to_keycode(keysym);
            if (code != 0) {
                /* we already have a keycode for this keysym */
                /* Does it need a shift key though ? */
                if (this.xdisplay.keycode_to_keysym (code, 0) != keysym) {
                    /* TODO: Assumes 1st modifier is shifted  */
                    if (this.xdisplay.keycode_to_keysym (code, 1) == keysym) {
                        flags |= Gdk.ModifierType.SHIFT_MASK; 	/* can get at it via shift */
                    } else {
                        code = 0; /* urg, some other modifier do it the heavy way */
                    }
                } else {
                    /* the keysym is unshifted; clear the shift flag if it is set */
                    /* TODO: Make sure hotkeys with Shift are still working  */
                    flags &= ~Gdk.ModifierType.SHIFT_MASK;
                }
            }

            if (code == 0) {
                int index;
     
                /* Change one of the last 10 keysyms to our converted utf8,
                 * remapping the x keyboard on the fly. 
                 *
                 * This make assumption the last 10 arn't already used.
                 * TODO: probably safer to check for this. 
                 */
                this.modified_key = (this.modified_key + 1) % 10;
     
                /* Point at the end of keysyms, modifier 0 */
                index = (this.max_keycode - this.min_keycode - this.modified_key - 1) * this.n_keysyms_per_keycode;
                this.keysyms[index] = keysym;
                
                // Use custom vapi because these functions are not included in x11 vapi.
                change_keyboard_mapping(this.xdisplay, this.min_keycode, this.n_keysyms_per_keycode, this.keysyms, this.max_keycode - this.min_keycode);
                // Sync for the mapping change to be effective now
                sync(this.xdisplay, false);

                code = this.xdisplay.keysym_to_keycode(keysym);
                if (this.xdisplay.keycode_to_keysym (code, 0) != keysym) {
                    /* TODO: Assumes 1st modifier is shifted  */
                    if (this.xdisplay.keycode_to_keysym (code, 1) == keysym) {
                        flags |= Gdk.ModifierType.SHIFT_MASK; 	/* can get at it via shift */
                    } else {
                        debug("Attempted to add keycode to keymap but seem to have failed");
                        code = 0;
                    }
                }
            }

            if (code != 0) {
                send_keyevent(code, true, flags);

                held_state_flags = flags;
                held_keycode     = code;
                return true;
            }
            held_state_flags = 0;
            held_keycode     = 0;
            return false; 			/* failed */
        }
        
        public bool press_and_release (ulong keysym, Gdk.ModifierType flags) {
            bool res = press(keysym, flags);
            release();
            return res;
        }
        
        public void release() {
            if (!(held_keycode > 0)) {
                return;
            }
            send_keyevent(held_keycode, false, held_state_flags);
            held_state_flags = 0;
            held_keycode     = 0;
        }
        
        public void repeat() {
            if (!(held_keycode > 0)) {
                return;
            }
            send_keyevent(held_keycode, true, held_state_flags);
        }
    }
    
    int main(){return 0;}
}
