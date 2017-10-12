using GnuTLS;

namespace Gconnect.Config {
    
    public string parse_dbus_path (string path) {
        // TODO: replace characters that are not allowed as a dbus or GSettings path
        return GLib.DBus.address_escape_value(path);
    }

    Config __instance = null;

    public class Config : Object {
        private GLib.Settings settings;
        private GLib.Settings root_devices_settings;
        private Gee.HashMap<string, GLib.Settings> devices_settings;
        private string _device_category = "desktop";
        private string settings_name = SETTINGS_NAME;
     
        public TlsCertificate certificate { get; private set; default = null; }
        
        public string device_name {get; set;}

        public string device_id {get; private set;}
        
        public string device_category {
            get { return _device_category;}
        }

        private Config() {
            init_user_dirs();
            this.settings = new Settings(settings_name);
            this.settings.bind("name", this, "device_name", SettingsBindFlags.DEFAULT);
            this.settings.bind("id", this, "device_id", SettingsBindFlags.SET);
            if (!Guuid.is_valid(this.settings.get_string("id"))) {
                device_id = Guuid.random();
                info("Generate new uuid for the local server: %s", device_id);
            } else {
                device_id = this.settings.get_string("id");
            }
            this.root_devices_settings = new Settings(settings_name + ".paired-devices");
            this.devices_settings = new Gee.HashMap<string, GLib.Settings>();

 			try {
                init_crypto();
            } catch (Error e) {
                warning("Could not load the certificate: %s", e.message);
            }

            load_paired_devices();
        }

        public static Config instance() {
            if (__instance == null) {
                var conf = new Config();
                __instance = conf;
            }
            return __instance;
        }

        public string[] get_paired_devices() {
            return this.settings.get_strv("paired-devices");
        }       

        public bool is_paired(string id) {
            var paired = new Gee.ArrayList<string>.wrap(this.get_paired_devices());
            return paired.contains(id);
        } 
              
        public bool has_certificate(string id) {
            if (is_paired(id)) {
                var dev = devices_settings[id];
                string? cert = dev.get_string("encryption-info");
                if (cert != null) {
                    return true;
                }
            }
            return false;
        }       

        internal bool check_certificate(string id, TlsCertificate cert, TlsCertificateFlags? errors = null) throws TlsError {
            if (!has_certificate(id)) {
                return false;
            }
            var dev = devices_settings[id];
            string stored_cert_pem = dev.get_string("encryption-info");
            
            var stored_cert = new TlsCertificate.from_pem(stored_cert_pem, stored_cert_pem.length);
            bool is_same = stored_cert.is_same(cert);
            
            if (!stored_cert.is_same(cert)) {
                throw new TlsError.HANDSHAKE("Stored certificate for paired device %s is different from received certificate".printf(id));
            }
            return true;
        }       

        public bool set_certificate_for_device(string id, string cert) {
            if (is_paired(id)) {
                var dev = devices_settings[id];
                dev.set_string("encryption-info", cert);
                dev.apply();
                return true;
            }
            return false;
        }       

        public string[] get_auto_pair_devices() {
            return this.settings.get_strv("auto-pair-devices");
        }       

        public void add_paired_device (string raw_id, DeviceManager.DeviceInfo dev_info) throws IOError {
            // Use a gsettings-compatible id.
            string id = parse_dbus_path(raw_id);

            var paired = new Gee.ArrayList<string>.wrap(this.get_paired_devices());
            
            if (!paired.contains(id)) {
                paired.add(id);
            }

            string new_path = this.settings.path + "devices/";
            var dev = new Settings.with_path(settings_name + ".device", new_path + id + "/");
            dev.set_string("id", raw_id);
            dev.set_string("name", dev_info.name);
            dev.set_string("type", dev_info.category);
            dev.set_int("protocol-version", dev_info.protocol_version);
            dev.set_strv("incoming-capabilities", dev_info.incoming);
            dev.set_strv("outgoing-capabilities", dev_info.outgoing);
            // Lan
            if (dev_info.encryption != "") {
                dev.set_string("encryption-info", dev_info.encryption);
            }
            if (dev_info.ip_address != "") {
                dev.set_string("ip-address", dev_info.ip_address);
            }

            devices_settings[id] = dev;
            dev.apply();
            
            this.settings.set_strv("paired-devices", paired.to_array());
            this.settings.apply();
            message("New trusted device added:\n%s", dev_info.to_string());
        }
        
        public void remove_paired_device (string raw_id) throws IOError {
            // Use a gsettings-compatible id.
            string id = parse_dbus_path(raw_id);

            var paired = new Gee.ArrayList<string>.wrap(this.get_paired_devices());
            if (!paired.contains(id)) {
                return;
            }
            if (!paired.remove(id)) {
                throw new IOError.FAILED("Could not remove id %s from the paired devices list: %s",
                        id, string.joinv(";", paired.to_array()));
            }
            var dev = devices_settings[id];
            dev.reset("id");
            dev.reset("name");
            dev.reset("type");
            dev.reset("protocol-version");
            dev.reset("incoming-capabilities");
            dev.reset("outgoing-capabilities");
            // Lan
            dev.reset("ip-address");
            dev.reset("encryption-info");
            dev.apply();
            devices_settings.unset(id);
            
            this.settings.set_strv("paired-devices", paired.to_array());
            this.settings.apply();
        }
        
        public DeviceManager.DeviceInfo get_paired_device(string raw_id) throws IOError {
            // Use a gsettings-compatible id.
            string id = parse_dbus_path(raw_id);

            DeviceManager.DeviceInfo dev_info = {};
            if (is_paired(id)) {
                var dev = devices_settings[id];
                dev_info.name = dev.get_string("name");
                dev_info.category = dev.get_string("type");
                dev_info.protocol_version = dev.get_int("protocol-version");
                dev_info.incoming = dev.get_strv("incoming-capabilities");
                dev_info.outgoing = dev.get_strv("outgoing-capabilities");
                // Lan
                dev_info.ip_address = dev.get_string("ip-address");
                dev_info.encryption = dev.get_string("encryption-info");
            } else {
                throw new IOError.FAILED("Could not retrieve device id %s from the paired devices list: %s",
                        id, string.joinv(";", devices_settings.keys.to_array()));
            }
            
            return dev_info;
        }
        
        private void load_paired_devices() {
            var paired = new Gee.ArrayList<string>.wrap(this.get_paired_devices());
            string new_path = this.settings.path + "devices/";
            foreach (var id in paired) {
                var dev = new Settings.with_path(settings_name + ".device", new_path + id + "/");
                devices_settings[id] = dev;
            }
        }

        public static string get_settings_path() {
            return SETTINGS_PATH;
        }
        
        public static string get_storage_dir() {
            return Path.build_filename(Environment.get_user_data_dir(),
                                    PACKAGE_NAME);
        }

        public static string get_config_dir() {
            return Path.build_filename(Environment.get_user_config_dir(),
                                    PACKAGE_NAME);
        }

        public static string get_cache_dir() {
            return Path.build_filename(Environment.get_user_cache_dir(),
                                    PACKAGE_NAME);
        }

        public static string get_plugins_local_dir() {
            return Path.build_filename(get_storage_dir(), "/plugins");
        }

        public static string get_plugins_global_dir() {
            return Path.build_filename(PACKAGE_PLUGINSDIR);
        }

        public string[] get_plugins_extra_dirs() {
            var plugins_settings = this.settings.get_child("plugins");
            return plugins_settings.get_strv("plugins-dirs");
        }

        private static void init_user_dirs() {
            DirUtils.create_with_parents(get_storage_dir(), 0700);
            DirUtils.create_with_parents(get_config_dir(), 0700);
        }

        private static string get_private_key_path() {
            return Path.build_filename(get_storage_dir(), "/private.pem");
        }
        
        private static string get_certificate_path() {
            return Path.build_filename(get_storage_dir(), "/certificate.pem");
        }
        
        private void init_crypto() throws Error {
            string key_path = get_private_key_path();
            string crt_path = get_certificate_path();
            
            bool res = true;
            int res2 = 0;
            GLib.File file = null;
            var key_file = File.new_for_path(key_path);
            var cert_file = File.new_for_path(crt_path);
            
            if (!key_file.query_exists() || !cert_file.query_exists()) {
                    try {
                        Crypt.generate_key_cert(key_file.get_path(),
                                                cert_file.get_path(),
                                                device_id);
                    } catch (Error e) {
                        warning("failed to generate private key or certificate: %s", e.message);
                        throw e;
                    }
            }

            // For testing, use certtool to generate a GnuTls certificate:
            // certtool --generate-privkey --bits 2048 --outfile private.pem
            // certtool --generate-self-signed --load-privkey private.pem --template template.cfg --outfile certificate.pem --hash SHA256 -q
//            GLib.Environment.set_variable("G_TLS_GNUTLS_PRIORITY", "NONE:+VERS-TLS1.0:+MAC-ALL:+ECDHE-ECDSA:+ECDHE-RSA:+AES-256-GCM:+AES-128-GCM:+AES-128-CBC:+ARCFOUR-128:+RSA:+SHA1:+SIGN-ALL:+COMP-NULL:+CURVE-ALL:+CTYPE-ALL", true); 
            certificate = new TlsCertificate.from_files(crt_path, key_path);
            GLib.info("Certificate loaded from pem file.");
        }
    }
}
