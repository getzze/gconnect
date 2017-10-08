
import gi
gi.require_version('Gconnect', '0.1')
gi.require_version('Peas', '1.0')

from gi.repository import GObject
from gi.repository import Gio
from gi.repository import GLib
from gi.repository import Peas
from gi.repository import Gconnect

import json
import logging

def packet_to_dict(pkt: Gconnect.NetworkProtocolPacket) -> dict:
    return json.loads(pkt.serialize())["body"]

def dict_to_packet(head: str, d: dict) -> Gconnect.NetworkProtocolPacket:
    s = json.dumps(d)
    pkt = Gconnect.NetworkProtocolPacket.with_string_body(head, s)
    return pkt

def prepare_logger(name):
    logger = logging.getLogger("gconnect.plugin.{}".format(name))
    logger.setLevel(logging.DEBUG)
    logformatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
    stream_handler = logging.StreamHandler()
    stream_handler.setLevel(logging.DEBUG)
    stream_handler.setFormatter(logformatter)
    logger.addHandler(stream_handler)
    return logger

class SimpleProxy:
    def __init__(self, proxy):
        self.proxy = proxy
        self.name = self.proxy.get_name()
        self.logger = prepare_logger(self.name)
        if not hasattr(self, "PACKET_TYPE_REQUEST"):
            raise NotImplementedError("The PACKET_TYPE_REQUEST attribute must be defined")
        self.proxy.connect("received_packet", self.receive)

    def formatted_receive(self, body):
        raise NotImplementedError("This method must be overridden")

    ### This should not be modified
    def formatted_request(self, d):
        try:
            self.proxy.request(dict_to_packet(self.PACKET_TYPE_REQUEST, d))
        except (TypeError, AttributeError) as err:
            self.logger.exception("Could not send packet")
        
    # Treat a received packet
    def receive(self, sender, pkt: Gconnect.NetworkProtocolPacket):
        self.formatted_receive(packet_to_dict(pkt))

    def disconnect(self):
        pass


class DbusProxy(SimpleProxy):
    def __init__(self, proxy):
        super(DbusProxy, self).__init__(proxy)
        self.dbus_published = False
        node_info = Gio.DBusNodeInfo.new_for_xml(self.introspection_xml())
        self.interface_info = node_info.interfaces[0]
        for method in self.interface_info.methods:
            name = self.get_dbus_method(method.name)
            if not hasattr(self, name):
                # The DBus methods must be defined, taking two parameters:
                #   param (GVariant tuple) and invocation (Gio.DBusMethodInvocation object)
                raise NotImplementedError("The dbus method {} must be implemented in the subclass".format(name))
        
        if self.proxy.dbus_connection() != None:
            self.publish(None)
        else:
            #Delayed publication on DBus
            self.proxy.connect("published", self.publish)

    def dbus_interface(self):
        return "org.gconnect.plugin.{}".format(self.name)

    def get_dbus_method(self, name):
        return "m_dbus_" + name
    
    def introspection_xml(self):
        """
        Use the dbus_interface method to format the output text
        """
        raise NotImplementedError('This method must be overridden')

    def emit_dbus_signal(self, name, variant_type, variant_value):
        """
        Emit a signal `name` (in camelCase) where variant_type must be a tuple of values,
        e.g. "(b)" and variant_value the value tuple, e.g. (True,)
        """
        if self.dbus_published:
            try:
                var = GLib.Variant(variant_type, variant_value)
                if not var.get_type().is_tuple():
                    raise TypeError("Variant not of tuple type, add parenthesis around the variant_type and the variant_value should be a tuple")
                self.proxy.emit_signal(self.dbus_interface(), name, var)
            except (TypeError, AttributeError) as err:
                self.logger.exception("Could not emit signal")

    def publish(self, sender):
        def method_call_cb(connection, sender, object_path, interface_name, method_name, parameters, invocation, *user_data):
            getattr(self, self.get_dbus_method(method_name))(parameters, invocation, *user_data)

        try:
            self.proxy.register_object(
                self.interface_info,
                method_call_cb,
                None,
                None)
        except (TypeError, AttributeError):
            self.logger.exception("Could not register object")
        else:
            self.dbus_published = True
            self.proxy.log("Publish interface {} to dbus".format(self.interface_info.name))

    def disconnect(self):
        if self.proxy and hasattr(self.proxy, "unpublish"):
            try:
                self.proxy.unpublish()
            except (TypeError, AttributeError):
                self.logger.exception("Could not unregister object")

