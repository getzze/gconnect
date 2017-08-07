[CCode (gir_namespace = "MyProject", gir_version = "1.0")]
namespace MyProject {
    public class MyClass : Object {
        public int fooed {
            public get; public set; default = 0;
        }

        public void foo () {
            stdout.printf (_ ("I did foo! What about you?\n"));
            this.fooed++;
        }

        public void foo_silent () {
            this.fooed++;
        }
    }
}