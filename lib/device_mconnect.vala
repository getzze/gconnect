/* ex:ts=4:sw=4:sts=4:et */
/* -*- tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*- */
/**
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * AUTHORS
 * Maciek Borzecki <maciek.borzecki (at] gmail.com>
 */

using Gee;
using Mconn;

/**
 * General device wrapper.
 */
class Device : DevicePluginProxy {

	public const uint PAIR_TIMEOUT = 30;

	public signal void paired(bool pair);
	public signal void connected();
	public signal void disconnected();
	public signal void message(Packet pkt);
	public signal void received(Packet pkt);
	/**
	 * capability_added:
	 * @cap: device capability, eg. kdeconnect.notification
	 *
	 * Device capability was added
	 */
	public signal void capability_added(string cap);
	/**
	 * capability_removed:
	 * @cap: device capability, eg. kdeconnect.notification
	 *
	 * Device capability was removed
	 */
	public signal void capability_removed(string cap);

	public string device_id { get; private set; default = ""; }
	public string device_name { get; private set; default = ""; }
	public string device_type { get; private set; default = ""; }
	public uint protocol_version {get; private set; default = 5; }
	public uint tcp_port {get; private set; default = 1714; }
	public InetAddress host { get; private set; default = null; }
	public bool is_paired { get; private set; default = false; }
	public bool allowed {get; set; default = false; }
	public bool is_active { get; private set; default = false; }

	public ArrayList<string> outgoing_capabilities {
		get;
		private set;
		default = null;
	}
	public ArrayList<string> incoming_capabilities {
		get;
		private set;
		default = null;
	}
	private Peas.ExtensionSet _extension_set;
    
	private HashSet<string> _capabilities = null;

	public string public_key {get; private set; default = ""; }

	// set to true if pair request was sent
	private bool _pair_in_progress = false;
	private uint _pair_timeout_source = 0;

	private DeviceChannel _channel = null;

	private Device() {
		incoming_capabilities = new ArrayList<string>();
		outgoing_capabilities = new ArrayList<string>();
		_capabilities = new HashSet<string>();
        attach_extensions();
    }

	/**
	 * Constructs a new Device wrapper based on identity packet.
	 *
	 * @param pkt identity packet
	 * @param host source host that the packet came from
	 */
	public Device.from_discovered_device(DiscoveredDevice disc) {
		this();

		this.host = disc.host;
		this.device_name = disc.device_name;
		this.device_id = disc.device_id;
		this.device_type = disc.device_type;
		this.protocol_version = disc.protocol_version;
		this.tcp_port = disc.tcp_port;
		this.outgoing_capabilities = new ArrayList<string>.wrap(
			disc.outgoing_capabilities);
		this.incoming_capabilities = new ArrayList<string>.wrap(
			disc.incoming_capabilities);

		debug("new device: %s", this.to_string());
	}

	/**
	 * Constructs a new Device wrapper based on data read from device
	 * cache file.
	 *
	 * @cache: device cache file
	 * @name: device name
	 */
	public static Device? new_from_cache(KeyFile cache, string name) {
		debug("device from cache group %s", name);

		try {
			var dev = new Device();
			dev.device_id = cache.get_string(name, "deviceId");
			dev.device_name = cache.get_string(name, "deviceName");
			dev.device_type = cache.get_string(name, "deviceType");
			dev.protocol_version = cache.get_integer(name, "protocolVersion");
			dev.tcp_port = (uint) cache.get_integer(name, "tcpPort");
			var last_ip_str = cache.get_string(name, "lastIPAddress");
			debug("last known address: %s:%u", last_ip_str, dev.tcp_port);
			dev.allowed = cache.get_boolean(name, "allowed");
			dev.is_paired = cache.get_boolean(name, "paired");
			dev.public_key = cache.get_string(name, "public_key");
			dev.outgoing_capabilities =	new ArrayList<string>.wrap(
				cache.get_string_list(name,
									  "outgoing_capabilities"));
			dev.incoming_capabilities =	new ArrayList<string>.wrap(
				cache.get_string_list(name,
									  "incoming_capabilities"));

			var host = new InetAddress.from_string(last_ip_str);
			if (host == null) {
				debug("failed to parse last known IP address (%s) for device %s",
					  last_ip_str, name);
				return null;
			}
			dev.host = host;

			return dev;
		}
		catch (KeyFileError e) {
			warning("failed to load device data from cache: %s", e.message);
			return null;
		}
	}

	~Device() {

	}

	private void attach_extensions() {
        var core = Core.instance();
        Type t = typeof (DeviceActivatable);
        info("Extension set for interface: %s (%s)", t.name(), t.is_interface().to_string());
        _extension_set = new Peas.ExtensionSet(core.plugin_manager.engine, typeof (DeviceActivatable), "device", this);
        _extension_set.extension_added.connect((info, extension) => {
            debug("Extension added for interface %s from plugin: %s", typeof(DeviceActivatable).name(), info.get_name() );
            (extension as DeviceActivatable).activate();
        });
        _extension_set.extension_removed.connect((info, extension) => {
            (extension as DeviceActivatable).deactivate();
        });
        this.request_made.connect(this.handle_request);
    }

    /**
	 * Generates a unique string for this device
	 */
	public string to_unique_string() {
		return make_unique_device_string(this.device_id,
										 this.device_name,
										 this.device_type,
										 this.protocol_version);
	}

	public string to_string() {
		return make_device_string(this.device_id, this.device_name,
								  this.device_type, this.protocol_version);
	}

	/**
	 * Dump device information to cache
	 *
	 * @cache: device cache
	 * @name: group name
	 */
	public void to_cache(KeyFile cache, string name) {
		cache.set_string(name, "deviceId", this.device_id);
		cache.set_string(name, "deviceName", this.device_name);
		cache.set_string(name, "deviceType", this.device_type);
		cache.set_integer(name, "protocolVersion", (int) this.protocol_version);
		cache.set_integer(name, "tcpPort", (int) this.tcp_port);
		cache.set_string(name, "lastIPAddress", this.host.to_string());
		cache.set_boolean(name, "allowed", this.allowed);
		cache.set_boolean(name, "paired", this.is_paired);
		cache.set_string(name, "public_key", this.public_key);
		cache.set_string_list(name, "outgoing_capabilities",
							  array_list_to_list(this.outgoing_capabilities));
		cache.set_string_list(name, "incoming_capabilities",
							  array_list_to_list(this.incoming_capabilities));
	}

	private async void greet() {
		var core = Core.instance();
		string host_name = Environment.get_host_name();
		string user = Environment.get_user_name();
        var config_id = core.config.get_device_name();
        config_id = config_id ?? @"mconnect:$user@$host_name";
        var config_name = core.config.get_device_name();
        config_name = config_name ?? host_name;
        var caps = core.plugin_manager.capabilities;
        
		yield _channel.send(Packet.new_identity(config_id, config_name, caps, caps));
		this.maybe_pair();
	}

	/**
	 * pair: sent pair request
	 *
	 * Internally changes pair requests state tracking.
	 *
	 * @param expect_response se to true if expecting a response
	 */
	public async void pair(bool expect_response = true) {
		if (this.host != null) {
			debug("start pairing");

			var core = Core.instance();
			string pubkey = core.crypt.get_public_key_pem();
			debug("public key: %s", pubkey);

			if (expect_response == true) {
				_pair_in_progress = true;
				// pairing timeout
				_pair_timeout_source = Timeout.add_seconds(PAIR_TIMEOUT,
														   this.pair_timeout);
			}
			// send request
			yield _channel.send(Packet.new_pair(pubkey));
		}
	}

	private bool pair_timeout() {
		warning("pair request timeout");

		_pair_timeout_source = 0;

		// handle failed pairing
		handle_pair(false, "");

		// remove timeout source
		return false;
	}

	/**
	 * maybe_pair:
	 *
	 * Trigger pairing or call handle_pair() if already paired.
	 */
	public void maybe_pair() {
		if (is_paired == false) {
			if (_pair_in_progress == false)
				this.pair.begin();
		} else {
			// we are already paired
			handle_pair(true, this.public_key);
		}
	}

	/**
	 * activate:
	 *
	 * Activate device. Triggers sending of #paired signal after
	 * successfuly opening a connection.
	 */
	public void activate() {
		if (_channel != null) {
			debug("device %s already active", this.to_string());
		}

		var core = Core.instance();
		_channel = new DeviceChannel(this.host, this.tcp_port,
									 core.crypt);
		_channel.disconnected.connect((c) => {
				this.handle_disconnect();
			});
		_channel.packet_received.connect((c, pkt) => {
				this.packet_received(pkt);
			});
		_channel.open.begin((c, res) => {
				this.channel_openend(_channel.open.end(res));
			});
        
		this.is_active = true;
	}

	/**
	 * deactivate:
	 *
	 * Deactivate device
	 */
	public void deactivate() {
		if (_channel != null) {
			close_and_cleanup();
		}
	}

    /**
	 * channel_openend:
	 *
	 * Callback after DeviceChannel.open() has completed. If the
	 * channel was successfuly opened, proceed with handshake.
	 */
	private void channel_openend(bool result) {
		debug("channel openend: %s", result.to_string());

		connected();

		if (result == true) {
			greet.begin();
		} else {
			// failed to open channel, invoke cleanup
			channel_closed_cleanup();
		}
	}

	/**
	 * Send normal packet through channel
	 */
	public async void send_packet(Packet pkt) {
        if (pkt.pkt_type in incoming_capabilities) {
            yield _channel.send(pkt);
        } else {
            info("Device %s does not accept incoming packet of type %s", this.device_name, pkt.pkt_type);
        };
	}

	private void packet_received(Packet pkt) {
		vdebug("got packet");
		if (pkt.pkt_type == Packet.PAIR) {
			// pairing
			handle_pair_packet(pkt);
		} else {
			// we sent a pair request, but got another packet,
			// supposedly meaning we're alredy paired since the device
			// is sending us data
			if (this.is_paired == false) {
				warning("not paired and still got a packet, " +
						"assuming device is paired",
						Packet.PAIR);
				handle_pair(true, "");
			}

            // deliver packet to the associated plugins
            this.handle_plugin_packet(pkt);
		}
	}

	/**
	 * handle_pair_packet:
	 *
	 * Handle incoming packet of Packet.PAIR type. Inside, try to
	 * guess if we got a response for a pair request, or is this an
	 * unsolicited pair request coming from mobile.
	 */
	private void handle_pair_packet(Packet pkt) {
		assert(pkt.pkt_type == Packet.PAIR);

		bool pair = pkt.body.get_boolean_member("pair");
		string public_key = "";
		if (pair) {
			public_key = pkt.body.get_string_member("publicKey");
		}

		handle_pair(pair, public_key);
	}

	/**
	 * handle_pair:
	 * @pair: pairing status
	 * @public_key: device public key
	 *
	 * Update device pair status.
	 */
	private void handle_pair(bool pair, string public_key) {
		if (this._pair_timeout_source != 0) {
			Source.remove(_pair_timeout_source);
			this._pair_timeout_source = 0;
		}

		debug("pair in progress: %s is paired: %s pair: %s",
			  _pair_in_progress.to_string(), this.is_paired.to_string(),
			  pair.to_string());
		if (_pair_in_progress == true) {
			// response to host initiated pairing
			if (pair == true) {
				debug("device is paired, pairing complete");
				this.is_paired = true;
			} else {
				warning("pairing rejected by device");
				this.is_paired = false;
			}
			// pair completed
			_pair_in_progress = false;
		} else {
			debug("unsolicited pair change from device, pair status: %s",
				  pair.to_string());
			if (pair == false) {
				// unpair from device
				this.is_paired = false;
			} else {
				// split brain, pair was not initiated by us, but we were called
				// with information that we are paired, assume we are paired and
				// send a pair packet, but not expecting a response this time

				this.pair.begin(false);

				this.is_paired = true;
			}
		}

		if (pair) {
			// update public key
			this.public_key = public_key;
		} else {
			this.public_key = "";
		}

		// emit signal
		paired(is_paired);
	}

	/**
	 * handle_disconnect:
	 *
	 * Handler for received() signal
	 */
	private void handle_disconnect() {
		// channel got disconnected
		debug("channel disconnected");
		close_and_cleanup();
	}

	/**
	 * handle_plugin_packet:
	 *
	 * Handler for received packet that are redirected to plugins
	 */
	private void handle_plugin_packet(Packet pkt) {
        // Only treat packets if the device is paired
        if (!this.is_paired) {
            return;
        }
        // emit signal
        received(pkt);
        string type = pkt.pkt_type;
        if (type.has_suffix(".request")) {
            type = type.replace(".request", "");
        }
        /* TODO add filter to capabilities of the server
        * if (!(type in this._capabilities)) {
        *     return;
        * }
        */
        var body = pkt.body;
        debug("Transmit packet to plugins of type %s", type);
        
        this._extension_set.@foreach((ext_set, info, extension) => {
            bool is_debug_plugin = bool.parse(info.get_external_data("X-Debug"))==true;
            bool is_matched_plugin = info.get_external_data("X-Type")==type;
            if ( is_debug_plugin || is_matched_plugin ) {
                (extension as DeviceActivatable).receive(body);
            }
        });
    }

    private void handle_request(string type, Json.Object body) {
        this.send_packet(new Packet(type, body));
    }

    private void close_and_cleanup() {
		_channel.close();
		channel_closed_cleanup();
	}

	/**
	 * channel_closed_cleanup:
	 *
	 * Single cleanup point after channel has been closed
	 */
	private void channel_closed_cleanup() {
		debug("close cleanup");
		_channel = null;

		this.is_active = false;

		// emit disconnected
		disconnected();
	}


	/**
	 * update_from_device:
	 * @other_dev: other device
	 *
	 * Update information/state of this device using data from @other_dev. This
	 * may happen in case when a discovery packet was received, or a device got
	 * connected. In such case, a `this` device (which was likely created from
	 * cached data) needs to be updated.
	 */
	public void update_from_device(Device other_dev) {
		if (this.host != null && this.host.to_string() != other_dev.host.to_string()) {
			debug("host address changed from %s to %s",
				  this.host.to_string(), other_dev.host.to_string());
			// deactivate first
			this.deactivate();

			host = other_dev.host;
			tcp_port = other_dev.tcp_port;
		}
	}
}

/**
 * General device wrapper.
 */
[DBus (name = "org.mconnect.Device")]
class DeviceDBusProxy : Object {

	public string id {
		get { return device.device_id; }
		private set {}
		default = "";
	}
	public string name {
		get { return device.device_name; }
		private set {}
		default = "";
	}
	public string device_type {
		get { return device.device_type; }
		private set {}
		default = "";
	}
	public uint protocol_version {
		get { return device.protocol_version; }
		private set {}
		default = 5;
	}
	public string address { get; private set; default = ""; }

	public bool is_paired {
		get { return device.is_paired; }
		private set {}
		default = false;
	}
	public bool allowed {
		get { return device.allowed; }
		private set {}
		default = false;
	}
	public bool is_active {
		get { return device.is_active; }
		private set {}
		default = false;
	}
	public bool is_connected { get; private set; default = false; }

	public string[] incoming_capabilities {
		get;
		private set;
	}

	public string[] outgoing_capabilities {
		get;
		private set;
	}

	private uint register_id = 0;

	private DBusPropertyNotifier prop_notifier = null;

	[DBus (visible = false)]
	public ObjectPath object_path = null;

	[DBus (visible = false)]
	public Device device {get; private set; default = null; }

	public static DeviceDBusProxy.for_device_with_path(Device device, ObjectPath path) {
		this.device = device;
		this.object_path = path;
		this.update_address();
		this.update_capabilities();
		this.device.notify.connect(this.param_changed);
		this.device.connected.connect(() => {
				this.is_connected = true;
			});
		this.device.disconnected.connect(() => {
				this.is_connected = false;
			});
		this.notify.connect(this.update_properties);
	}

	private void update_capabilities() {
		string[] caps = {};

		foreach (var cap in device.incoming_capabilities) {
			caps += cap;
		}
		this.incoming_capabilities = caps;

		caps = {};

		foreach (var cap in device.outgoing_capabilities) {
			caps += cap;
		}
		this.outgoing_capabilities = caps;
	}

	private void update_address() {
		this.address = "%s:%u".printf(device.host.to_string(),
									  device.tcp_port);
	}

	private void update_properties(ParamSpec param) {
		debug("param %s changed", param.name);

		string name = param.name;
		Variant v = null;
		switch (param.name) {
		case "address":
			v = this.address;
			break;
		case "id":
			v = this.id;
			break;
		case "name":
			v = this.name;
			break;
		case "device-type":
			name = "DeviceType";
			v = this.device_type;
			break;
		case "potocol-version":
			name = "ProtocolVersion";
			v = this.protocol_version;
			break;
		case "is-paired":
			name = "IsPaired";
			v = this.is_paired;
			break;
		case "allowed":
			v = this.allowed;
			break;
		case "is-active":
			name = "IsActive";
			v = this.is_active;
			break;
		case "is-connected":
			name = "IsConnected";
			v = this.is_connected;
			break;
		}

		if (v == null)
			return;

		this.prop_notifier.queue_property_change(name, v);
	}

	private void param_changed(ParamSpec param) {
		debug("parameter %s changed", param.name);
		switch (param.name) {
		case "host":
		case "tcp-port":
			this.update_address();
			break;
		case "allowed":
			this.allowed = device.allowed;
			break;
		case "is-active":
			this.is_active = device.is_active;
			break;
		case "is-paired":
			this.is_paired = device.is_paired;
			break;
		case "incoming-capabilities":
		case "outgoing-capabilities":
			this.update_capabilities();
			break;
		}
	}

	[DBus (visible = false)]
	public void bus_register(DBusConnection conn) {
		try {
			this.register_id = conn.register_object(this.object_path, this);
			this.prop_notifier = new DBusPropertyNotifier(conn,
														  "org.mconnect.Device",
														  this.object_path);
		} catch (IOError err) {
			warning("failed to register DBus object for device %s under path %s",
					this.device.to_string(), this.object_path.to_string());
		}
	}

	[DBus (visible = false)]
	public void bus_unregister(DBusConnection conn) {
		if (this.register_id != 0) {
			conn.unregister_object(this.register_id);
		}
		this.register_id = 0;
		this.prop_notifier = null;
	}

}
