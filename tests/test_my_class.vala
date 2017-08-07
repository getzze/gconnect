public class MyClassTest : TestCase {
    private MyProject.MyClass cut;

    public MyClassTest () {
        base ("my_class");
        add_test ("foo", test_foo);
    }

    public override void set_up () {
        this.cut = new MyProject.MyClass ();
    }

    public override void tear_down () {
    }

    public void test_foo () {
        this.cut.foo_silent ();
        assert (this.cut.fooed == 1);
    }
}