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
    logger = logging.getLogger(name)
    logger.setLevel(logging.DEBUG)
    logformatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
    stream_handler = logging.StreamHandler()
    stream_handler.setLevel(logging.DEBUG)
    stream_handler.setFormatter(logformatter)
    logger.addHandler(stream_handler)
    return logger

logger = prepare_logger(__name__)

gi.require_version('Notify', '0.7')
from gi.repository import Notify
from gi.repository import GdkPixbuf

Notify.init("Gconnect")

class SimpleProxy:
    def __init__(self, proxy):
        self.proxy = proxy
        self.name = self.proxy.get_name()
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
            logger.exception("Could not send packet")
        
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
                logger.exception("Could not emit signal")

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
            logger.exception("Could not register object")
        else:
            self.dbus_published = True
            self.proxy.log("Publish interface {} to dbus".format(self.interface_info.name))

    def disconnect(self):
        if self.proxy and hasattr(self.proxy, "unpublish"):
            try:
                self.proxy.unpublish()
            except (TypeError, AttributeError):
                logger.exception("Could not unregister object")
    

class BatteryProxy(DbusProxy):
    PACKET_TYPE_REQUEST = "kdeconnect.battery.request"

    def __init__(self, proxy):
        super(BatteryProxy, self).__init__(proxy)
        self.charge = -1
        self.is_charging = None
        self.formatted_request({"request": True})
        self.proxy.log("Plugin {} activated".format(self.name))

    def introspection_xml(self):
        return """
            <!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
            <node>
              <interface name="{}">
                <signal name="stateChanged">
                  <arg type="b" name="charging"/>
                </signal>
                <signal name="chargeChanged">
                  <arg type="i" name="charge"/>
                </signal>
                <method name="charge">
                  <arg type="i" name="result" direction="out"/>
                </method>
                <method name="isCharging">
                  <arg type="b" name="result" direction="out"/>
                </method>
                <method name="request">
                </method>
              </interface>
            </node>
            """.format(self.dbus_interface())

    def formatted_receive(self, body):
        if not body:
            return
        is_charging = body.get("isCharging", False)
        current_charge = body.get("currentCharge", -1)
        threshold_event = body.get("thresholdEvent", 0) # None=0, Low=1
        self.proxy.log("Battery {} ({}%)".format("charging" if is_charging else "discharging", current_charge))

        if ((current_charge > 0 and self.charge != current_charge) or self.is_charging != is_charging):
            self.is_charging = is_charging
            self.charge = current_charge
            self.emit_dbus_signal("stateChanged", "(b)", (self.is_charging,) )
            self.emit_dbus_signal("chargeChanged", "(i)", (self.charge,) )

        if threshold_event == 1 and not is_charging:
            title = "{}: low battery".format(device.name)
            mess = "Battery at {}%".format(current_charge)
            notification = Notify.Notification.new(title, mess)
            # Use GdkPixbuf to create the proper image type
            image = GdkPixbuf.Pixbuf.new_from_file("/usr/share/icons/Adwaita/16x16/devices/battery-symbolic.symbolic.png")
            # Use the GdkPixbuf image
            notification.set_icon_from_pixbuf(image)
            notification.set_image_from_pixbuf(image)

            notification.show()

    def m_dbus_charge(self, parameters, invocation, *user_data):
        invocation.return_value(GLib.Variant("(i)", (self.charge,)))

    def m_dbus_isCharging(self, parameters, invocation, *user_data):
        invocation.return_value(GLib.Variant("(b)", (self.is_charging,)))
    
    def m_dbus_request(self, parameters, invocation, *user_data):
        self.formatted_request({"request": True})
    

class BatteryPlugin(GObject.Object, Gconnect.PluginPlugin):
    __gtype_name__ = 'BatteryPlugin'
    CLASS_PROXY = BatteryProxy
    
    device = GObject.Property(type=Gconnect.DeviceManagerDevice)

    def __init__(self, *args, **kwargs):
        GObject.Object.__init__(self)

    def formatted_receive(self, body):
        self.proxy.formatted_receive(body)

    def do_activate(self, name: str):
        self.proxy = self.device.get_plugin(name)
        self.worker = self.CLASS_PROXY(self.proxy)
        
    def do_deactivate(self):
        if hasattr(self, "worker"):
            self.worker.disconnect()
            del self.worker
        if hasattr(self, "proxy"):
            del self.proxy
