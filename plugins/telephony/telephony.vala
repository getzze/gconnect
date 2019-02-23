using GLib;
using Peas;
using Gdk;
using Notify;
using Gconnect;

namespace PluginsGconnect.Telephony {
    
    public abstract class SimpleProxy : GLib.Object {
        protected unowned Gconnect.Plugin.PluginProxy proxy;
        protected string name;

        protected unowned DBusConnection dbus_connection;
        
        public SimpleProxy(Gconnect.Plugin.PluginProxy proxy) {
            this.proxy = proxy;
            this.name = proxy.name;
            this.proxy.received_packet.connect(receive);

            if (this.proxy.dbus_connection() != null) {
                publish();
            } else {
                // Delayed publication on DBus
                this.proxy.published.connect(publish);
            }
        }

        protected abstract void receive(Gconnect.NetworkProtocol.Packet pkt);
        protected abstract void publish();
        [DBus (visible = false)]
        public abstract void unpublish();
    }

    [DBus(name = "org.gconnect.plugins.telephony")]
    public class TelephonyProxy : SimpleProxy {
        protected const string PACKET_TYPE_TELEPHONY_REQUEST = "kdeconnect.telephony.request";
        protected const string PACKET_TYPE_SMS_REQUEST = "kdeconnect.sms.request";

        private Gee.HashMap<int, Notify.Notification> notifications = new Gee.HashMap<int, Notify.Notification>();
        
        
        public TelephonyProxy(Gconnect.Plugin.PluginProxy proxy) {
            Notify.init("gconnect");

            base(proxy);
        }

        public void send_sms(string phone_number, string message_body) {
            var pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_SMS_REQUEST);
            pkt.set_bool("sendSms", true);
            pkt.set_string("phoneNumber", phone_number);
            pkt.set_string("messageBody", message_body);
            this.proxy.request(pkt);
        }
        
        private void send_mute_packet() {
            var pkt = new Gconnect.NetworkProtocol.Packet(PACKET_TYPE_TELEPHONY_REQUEST);
            pkt.set_string("action", "mute");
            this.proxy.request(pkt);
        }

        private void show_send_sms_dialog(string phone_number, string contact_name, string message_body) {
            info("Reply to %s (%s) : %s", contact_name, phone_number, message_body);
    //            QString phoneNumber = sender()->property("phoneNumber").toString();
    //            QString contactName = sender()->property("contactName").toString();
    //            QString originalMessage = sender()->property("originalMessage").toString();
    //            SendReplyDialog* dialog = new SendReplyDialog(originalMessage, phoneNumber, contactName);
    //            connect(dialog, &SendReplyDialog::sendReply, this, &TelephonyPlugin::sendSms);
    //            dialog->show();
    //            dialog->raise();
        }

        private void create_notification(Gconnect.NetworkProtocol.Packet pkt) {
            string event = pkt.get_string("event");
            string phone_number = pkt.has_field("phoneNumber") ? pkt.get_string("phoneNumber") : "unknown number";
            string contact_name = pkt.has_field("contactName") ? pkt.get_string("contactName") : phone_number;
            Gdk.Pixbuf phone_thumbnail = null;
            if (pkt.has_field("phoneThumbnail")) {
    //                Pixbuf phone_thumbnail = QByteArray::fromBase64(np.get<QByteArray>(QStringLiteral("phoneThumbnail"), ""));
            }

            // In case telepathy can handle the message, don't do anything else
    //            if (event == "sms" && m_telepathyInterface.isValid()) {
    //                qCDebug(KDECONNECT_PLUGIN_TELEPHONY) << "Passing a text message to the telepathy interface";
    //                connect(&m_telepathyInterface, SIGNAL(messageReceived(QString,QString)), SLOT(sendSms(QString,QString)), Qt::UniqueConnection);
    //                const QString messageBody = np.get<QString>(QStringLiteral("messageBody"),QLatin1String(""));
    //                QDBusReply<bool> reply = m_telepathyInterface.call(QStringLiteral("sendMessage"), phoneNumber, contactName, messageBody);
    //                if (reply) {
    //                    return nullptr;
    //                } else {
    //                    qCDebug(KDECONNECT_PLUGIN_TELEPHONY) << "Telepathy failed, falling back to the default handling";
    //                }
    //            }

            string content, type, icon, message_body = "";
    //            KNotification::NotificationFlags flags = KNotification::CloseOnTimeout;

            string title = this.proxy.device_name;

            switch (event) {
            case "ringing":
                type = "callReceived";
                icon = "call-start";
                content = "Incoming call from %s".printf(contact_name);
                break;
            case "missedCall":
                type = "missedCall";
                icon = "call-start";
                content = "Missed call from %s".printf(contact_name);
    //                flags |= KNotification::Persistent; //Note that in Unity this generates a message box!
                break;
            case "sms":
                type = "smsReceived";
                icon = "mail-receive";
                message_body = pkt.has_field("messageBody") ? pkt.get_string("messageBody") : "";
                content = "SMS from %s<br>%s".printf(contact_name, message_body);
    //                flags |= KNotification::Persistent; //Note that in Unity this generates a message box!
                break;
            case "talking":
                return;
            default:
                type = "callReceived";
                icon = "phone";
                content = "Unknown telephony event: %s".printf(event);
                break;
            }

            debug("Creating notification with type: %s", type);

            Notify.Notification notification = new Notify.Notification (title, content, icon);
            notification.set_category(type);
            if (phone_thumbnail != null) {
                notification.set_image_from_pixbuf(phone_thumbnail);
            }

            if (event == "ringing") {
                notification.add_action("mute-call", "Mute call", (n, a) => {
                    this.send_mute_packet();
                    try { n.close(); } catch (Error e) {}
                    notifications.unset(n.id);
                });
            } else if (event == "sms") {
                notification.add_action("reply-sms", "Reply", (n, a) => {
                    this.show_send_sms_dialog(phone_number, contact_name, message_body);
                    try { n.close(); } catch (Error e) {}
                    notifications.unset(n.id);
                });
            }

            notifications.@set(notification.id, notification);
        }


        protected override void receive(Gconnect.NetworkProtocol.Packet pkt) {
            if (pkt.get_bool("isCancel")) {
                // close all notifications
                foreach (var key in notifications.keys) {
                    var n = notifications[key];
                    try { n.close(); } catch (Error e) {}
                    notifications.unset(key);
                }
            } else {
                create_notification(pkt);
            }
        }

        protected override void publish() {
            this.proxy.register(publish_dbus);
        }

        [DBus (visible = false)]
        public override void unpublish() {
            this.proxy.unpublish();
        }
        
        private uint publish_dbus(DBusConnection conn) throws IOError {
            this.dbus_connection = conn;

            string path = this.proxy.dbus_path();
            uint bus_id = conn.register_object(path, this);
            this.proxy.log("Publish interface to dbus path %s".printf(path));

            return bus_id;
        }
    }

    public class Telephony : GLib.Object, Gconnect.Plugin.Plugin {
        public unowned Gconnect.DeviceManager.Device device { get; construct set; }
        private TelephonyProxy worker = null;

        /* The "constructor" with the plugin name as argument */
        public void activate(string name) {
            this.worker = new TelephonyProxy(this.device.get_plugin(name));
        }
        
        public void deactivate() {
            if (this.worker != null) {
                this.worker.unpublish();
                this.worker = null;
            }
        }
    }
}

// Register extension types
[ModuleInit]
public void peas_register_types (TypeModule module) {
        var objmodule = module as Peas.ObjectModule;

        objmodule.register_extension_type(typeof (Gconnect.Plugin.Plugin), typeof (PluginsGconnect.Telephony.Telephony));
}
