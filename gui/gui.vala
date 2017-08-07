namespace MyProject.GUI {
    [GtkTemplate (ui = "/com/github/felipe-lavratti/vala-unittests-cmake/main-window.ui")]
    public class MainWindow : Gtk.ApplicationWindow {
        [GtkChild]
        private Gtk.ToggleButton toggle_button;

        public MainWindow () {
            var settings = new GLib.Settings ("com.github.felipe-lavratti.vala-unittests-cmake");
            settings.bind ("active", toggle_button, "active", GLib.SettingsBindFlags.DEFAULT);
        }
    }

    private class Application : Gtk.Application {
        protected override void activate () {
            var window = new MainWindow ();
            window.application = this;
            window.show ();
        }

        public Application () {
            Object (application_id: "org.github.felipe-lavratti.vala-unittests-cmake.gui");
        }
    }

    private static int main (string[] args) {
        var app = new MyProject.GUI.Application ();
        return app.run (args);
    }
}