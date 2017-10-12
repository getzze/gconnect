
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

class PingProxy(DbusProxy):
    PACKET_TYPE_REQUEST = "kdeconnect.ping"

    def __init__(self, proxy):
        super().__init__(proxy)
        self.proxy.log("Plugin {} activated".format(self.name))

    def introspection_xml(self):
        return """
            <!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
            <node>
              <interface name="{}">
                <method name="sendPing">
                </method>
                <method name="sendMessage">
                  <arg type="s" name="customMessage" direction="in"/>
                </method>
              </interface>
            </node>
            """.format(self.dbus_interface())

    def formatted_receive(self, body):
        title = "Ping!"
        try:
            title = "{}".format(self.proxy.get_device_name())
        except AttributeError:
            pass
        mess = body.get("message", "Ping!")
        notification = Notify.Notification.new(title, mess)
        # Use GdkPixbuf to create the proper image type
        image = GdkPixbuf.Pixbuf.new_from_file("/usr/share/icons/Adwaita/16x16/status/dialog-information-symbolic.symbolic.png")
        # Use the GdkPixbuf image
        notification.set_icon_from_pixbuf(image)
        notification.set_image_from_pixbuf(image)

        notification.show()

    def m_dbus_sendPing(self, parameters, invocation, *user_data):
        self.formatted_request({})
    
    def m_dbus_sendMessage(self, parameters, invocation, *user_data):
        mess = ""
        if parameters.n_children() > 0:
            cont = parameters.get_child_value(0)
            mess = cont.get_string()
        if mess:
            self.formatted_request({"message": mess})
        else:
            self.formatted_request({})
    

class PingPlugin(GObject.Object, Gconnect.PluginPlugin):
    __gtype_name__ = 'PingPlugin'
    CLASS_PROXY = PingProxy
    
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

