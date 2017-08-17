public class PacketTest : TestCase {
    private NetworkProtocol.Packet cut;

    public PacketTest () {
        base ("packet");
        add_test ("new", test_new);
    }

    public override void set_up () {
        this.cut = new NetworkProtocol.Packet ();
    }

    public override void tear_down () {
    }

    public void test_new () {
        this.cut.foo_silent ();
        assert (this.cut.fooed == 1);
    }
}
