import gi
gi.require_version('Gconnect', '0.1')

from gi.repository import GObject
from gi.repository import Gconnect

def packet_to_dict(np: Gconnect.NetworkProtocolPacket):
    return np

def dict_to_packet(d) -> Gconnect.NetworkProtocolPacket:
    return d

class ExamplePython(GObject.Object, Gconnect.PluginPlugin):
    __gtype_name__ = 'ExamplePythonPlugin'
    
    device = GObject.Property(type=Gconnect.DeviceManagerDevice)

    def formatted_receive(self, d):
        mess = d.get_string("debug")
        print(mess)

    def formatted_request(self, d):
        self.do_request(dict_to_packet(d))
        
    # Treat a received packet
    def do_receive(self, np: Gconnect.NetworkProtocolPacket):
        self.formatted_receive(packet_to_dict(np))

    def do_activate(self):
        print("{} plugin activated".format(self.__class__.__name__))

    def do_deactivate(self):
        print("{} plugin deactivated".format(self.__class__.__name__))

