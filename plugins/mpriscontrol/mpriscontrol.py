
import sys, os
import gi
gi.require_version('Gconnect', '0.1')

from gi.repository import GObject
from gi.repository import GLib
from gi.repository import Gconnect

import dbus
from dbus.mainloop.glib import DBusGMainLoop
#from pydbus import SessionBus
import re

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from helper import SimpleProxy

def parse_dbus_name(dbus_name):
    res = re.match("org.mpris.MediaPlayer2.(?P<name>.+)$", dbus_name)
    if res:
        return res.groupdict()["name"]
    return None

def parse_metadata(metadata):
    answer = {}
    if "xesam:title" in metadata:
        now_playing = metadata["xesam:title"]
        if "xesam:artist" in metadata:
            now_playing = " - ".join([metadata["xesam:artist"][0], now_playing])
        answer["nowPlaying"] = now_playing
    if "mpris:length" in metadata:
        answer["length"] = int(metadata["mpris:length"]/1000)
    return answer


class MprisControlProxy(SimpleProxy):
    PACKET_TYPE_REQUEST = "kdeconnect.mpris"

    def __init__(self, proxy):
        super(MprisControlProxy, self).__init__(proxy)
        self.player_list = {}
        self.service_signal = None
        self.previous_volume = None
        self.session = dbus.SessionBus(mainloop=DBusGMainLoop(set_as_default=True))
        #self.bus = SessionBus()
        self.watch_dbus()
        self.proxy.log("Plugin {} activated".format(self.name))

    def watch_dbus(self):
        self.service_signal = self.session.add_signal_receiver(self.on_name_owner_changed,
                dbus_interface='org.freedesktop.DBus', signal_name = "NameOwnerChanged")

        for dbus_name in self.session.list_names():
            # Fake a name acquired for all services already started
            self.on_name_owner_changed(dbus_name, "", "new")

    def on_name_owner_changed(self, dbus_name, old, new):
        name = parse_dbus_name(dbus_name)
        if name:
            if not old and new and name not in self.player_list:
                self.logger.debug("MPRIS service {} just came online".format(name))
                self.add_player(name)
            elif old and not new and name in self.player_list:
                self.logger.debug("MPRIS service {} just went offline".format(name))
                self.remove_player(name)

    def add_player(self, name):
        player = self.session.get_object('org.mpris.MediaPlayer2.{}'.format(name), '/org/mpris/MediaPlayer2')
        unique_name = str(player.bus_name)
        self.player_list[name] = dict()
        self.player_list[name]["alias"] = ['org.mpris.MediaPlayer2.{}'.format(name), unique_name]
        self.player_list[name]["object"] = player
        self.player_list[name]["signals"] = [
                self.session.add_signal_receiver(self.seeked, signal_name = "Seeked",
                            dbus_interface='org.mpris.MediaPlayer2.Player', sender_keyword='sender'),
                self.session.add_signal_receiver(self.properties_changed, signal_name = "PropertiesChanged",
                            dbus_interface='org.freedesktop.DBus.Properties', sender_keyword='sender')]
        
        self.send_player_list()

    def remove_player(self, name):
        for s in self.player_list[name]["signals"]:
            s.remove()
        del self.player_list[name]
        self.send_player_list()

    def send_player_list(self):
        self.formatted_request({"playerList": list(self.player_list.keys())})

    def seeked(self, position, sender=None, **kwargs):
        name = self.match_player(sender)
        if name and name in self.player_list:
            self.formatted_request({"player": name, "pos": position/1000})

    def properties_changed(self, interface, properties, *args, sender=None, **kwargs):
        name = self.match_player(sender)
        if not name or name not in self.player_list:
            return
        answer = dict()
        if "Volume" in properties:
            volume = int(properties["Volume"]*100)
            if volume != self.previous_volume:
                self.previous_volume = volume
                answer["volume"] = volume
        if "Metadata" in properties:
            metadata = properties["Metadata"]
            answer.update(parse_metadata(metadata))
        if "PlaybackStatus" in properties:
            answer["isPlaying"] = (properties["PlaybackStatus"] == "Playing")
        for prop in ["CanPause", "CanPlay", "CanGoNext", "CanGoPrevious", "CanSeek"]:
            if prop in properties:
                camel = prop[:1].lower() + prop[1:]
                answer[camel] = bool(properties[prop])

        if answer:
            answer["player"] = name
            property_interface = dbus.Interface(self.player_list[name]["object"], dbus_interface='org.freedesktop.DBus.Properties')
            can_seek = property_interface.Get('org.mpris.MediaPlayer2.Player', 'CanSeek')
            if can_seek:
                answer["pos"] = int(property_interface.Get('org.mpris.MediaPlayer2.Player', 'Position')/1000)
            
            self.formatted_request(answer)

    def match_player(self, sender):
        for k, d in self.player_list.items():
            if sender in d["alias"]:
                return k
        return None

    def formatted_receive(self, body):
        if "playerList" in body:
            # Whoever sent this is an mpris client and not an mpris control!
            return

        # Send the player list
        player_name = body.get("player")
        
        valid_player = player_name in self.player_list.keys()
        if not valid_player or body.get("requestPlayerList"):
            self.send_player_list();
            if not valid_player:
                return
        
        # Do something to the mpris interface
        player = self.player_list[player_name]["object"]
        player_interface = dbus.Interface(player, dbus_interface='org.mpris.MediaPlayer2.Player')
        property_interface = dbus.Interface(player, dbus_interface='org.freedesktop.DBus.Properties')
        if "action" in body:
            action = body.get("action")
            player_interface.get_dbus_method(action)()
        if "setVolume" in body:
            volume = body.get("setVolume")/100.
            property_interface.Set('org.mpris.MediaPlayer2.Player', 'Volume', volume)
        if "Seek" in body:
            offset = body.get("Seek")
            player_interface.Seek(offset)
        if "SetPosition" in body:
            position = body.get("SetPosition", 0)*1000
            player_interface.Seek(position - mpris_interface.position())

        # Send something read from the mpris interface
        answer = dict()
        if body.get("requestNowPlaying"):
            metadata = property_interface.Get('org.mpris.MediaPlayer2.Player', 'Metadata')
            answer.update(parse_metadata(metadata))
            answer["pos"] = int(property_interface.Get('org.mpris.MediaPlayer2.Player', 'Position')/1000)
            answer["isPlaying"] = property_interface.Get('org.mpris.MediaPlayer2.Player', 'PlaybackStatus') == "Playing"
            for prop in ["CanPause", "CanPlay", "CanGoNext", "CanGoPrevious", "CanSeek"]:
                camel = prop[:1].lower() + prop[1:]
                answer[camel] = bool(property_interface.Get('org.mpris.MediaPlayer2.Player', prop))
        if body.get("requestVolume"):
            volume = property_interface.Get('org.mpris.MediaPlayer2.Player', 'Volume') * 100
            answer["volume"] = volume

        if answer:
            answer["player"] = player_name
            self.formatted_request(answer)
    
    def disconnect(self):
        for d in self.player_list.values():
            for s in d["signals"]:
                s.remove()
        self.service_signal.remove()
        super(MprisControlProxy, self).disconnect()

class MprisControlPlugin(GObject.Object, Gconnect.PluginPlugin):
    __gtype_name__ = 'MprisControlPlugin'
    CLASS_PROXY = MprisControlProxy
    
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
