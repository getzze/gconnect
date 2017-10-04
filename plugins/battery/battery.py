
import sys, os
import gi
gi.require_version('Gconnect', '0.1')
gi.require_version('Notify', '0.7')

from gi.repository import GObject
from gi.repository import Gconnect
from gi.repository import Notify
from gi.repository import GdkPixbuf

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from helper import DbusProxy

Notify.init("Gconnect")


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
