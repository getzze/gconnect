namespace MyProject {
    public class Application {
        private static bool version;
        private static bool api_version;
        private const OptionEntry[] options = {
            { "version", 0, 0, OptionArg.NONE, ref version, "Display version number", null },
            { "api-version", 0, 0, OptionArg.NONE, ref api_version, "Display API version number", null },
            { null }
        };

        static int main (string[] args) {
            GLib.Intl.setlocale ();

            try {
                var opt_context = new OptionContext ("- My Project");
                opt_context.set_help_enabled (true);
                opt_context.add_main_entries (options, null);
                opt_context.parse (ref args);
            } catch (OptionError e) {
                stdout.printf ("%s\n", e.message);
                stdout.printf ("Run '%s --help' to see a full list of available command line options.\n", args[0]);
                return 1;
            }

            if (version) {
                stdout.printf ("My Project %s\n", Config.BUILD_VERSION);
                return 0;
            } else if (api_version) {
                stdout.printf ("%s\n", Config.PACKAGE_SUFFIX);
                return 0;
            }

            var foo = new MyClass ();
            foo.foo ();

            return 0;
        }
    }
}