{ config, ... }:
# Wi-Fi profiles that need credentials. The secrets live in secrets/nixos-laptop.yaml as one env
# file, decrypted at boot by sops-nix with this machine's SSH host key; NetworkManager substitutes
# the $VARS into the profiles when ensure-profiles runs. Single-quote values there: the eduroam
# password contains '#' and '&'.
{
  sops.defaultSopsFile = ../../secrets/nixos-laptop.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.wifi_env = { };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.secrets.wifi_env.path ];

    # eduroam with the UTokyo Wi-Fi account. Settings follow utelecon's Android guide
    # (https://utelecon.adm.u-tokyo.ac.jp/utokyo_wifi/android/): PEAP + MSCHAPv2, system CA
    # store, domain u-tokyo.ac.jp. The anonymous outer identity keeps the user ID out of the
    # clear-text EAP exchange (the same realm the iwd example by haxibami uses).
    profiles.eduroam = {
      connection = {
        id = "eduroam";
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        ssid = "eduroam";
        mode = "infrastructure";
      };
      wifi-security.key-mgmt = "wpa-eap";
      "802-1x" = {
        eap = "peap";
        phase2-auth = "mschapv2";
        identity = "$EDUROAM_IDENTITY";
        anonymous-identity = "anonymous@wifi.u-tokyo.ac.jp";
        password = "$EDUROAM_PASSWORD";
        ca-cert = "/etc/ssl/certs/ca-certificates.crt";
        domain-suffix-match = "u-tokyo.ac.jp";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };

    # The iPhone's Personal Hotspot, as the fallback uplink when nothing else is around. The
    # negative priority makes any other known network win when both are in range, and metered
    # tells NetworkManager-aware apps to hold back on large background transfers.
    profiles.iphone-hotspot = {
      connection = {
        id = "iPhone 9 Pro";
        type = "wifi";
        autoconnect = true;
        autoconnect-priority = -10;
        metered = 1;
      };
      wifi = {
        ssid = "iPhone 9 Pro";
        mode = "infrastructure";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$IPHONE_HOTSPOT_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };
}
