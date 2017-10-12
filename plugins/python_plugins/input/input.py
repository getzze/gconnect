
import sys, os
import gi
gi.require_version('Gconnect', '0.1')

from gi.repository import GObject
from gi.repository import Gconnect

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from helper import SimpleProxy

import pyautogui


class InputProxy(SimpleProxy):
    PACKET_TYPE_REQUEST = "kdeconnect.mousepad.request"
    PACKET_TYPE_ECHO = "kdeconnect.mousepad.echo";
    PACKET_TYPE_KEYBOARDSTATE = "kdeconnect.mousepad.keyboardstate";

    def __init__(self, proxy):
        super(InputProxy, self).__init__(proxy)

    def formatted_receive(self, body):
        dx = body.get("dx", 0)
        dy = body.get("dy", 0)

        isSingleClick = body.get("singleclick", False)
        isDoubleClick = body.get("doubleclick", False)
        isMiddleClick = body.get("middleclick", False)
        isRightClick = body.get("rightclick", False)
        isSingleHold = body.get("singlehold", False)
        isSingleRelease = body.get("singlerelease", False)
        isScroll = body.get("scroll", False)
        key = body.get("key", "")
        specialKey = body.get("specialKey", 0)
    

class InputPlugin(GObject.Object, Gconnect.PluginPlugin):
    __gtype_name__ = 'InputPlugin'
    CLASS_PROXY = InputProxy
    
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
