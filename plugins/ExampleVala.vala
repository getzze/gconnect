
using Gconnect;

class ExampleVala : Object, Gconnect.Plugin.Plugin {
    
    public Gconnect.DeviceManager.Device device { get; construct set; }

    void receive(Gconnect.NetworkProtocol.Packet pkt) {
        var mess = pkt.get_string("debug");
        message(mess);
    }

    void activate() {
        debug("ExampleVala plugin activated");
    }

    void deactivate() {
        debug("ExampleVala plugin deactivated");
    }
}

/* Register extension types */
[ModuleInit]
public void peas_register_types(TypeModule module) {
    var objmodule = module as Peas.ObjectModule;

    objmodule.register_extension_type(typeof (Gconnect.Plugin.Plugin), typeof (ExampleVala));
}
