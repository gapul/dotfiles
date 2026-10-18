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
        # 2.4 GHz only. The AP 74:a2:e6:38:20:3c/3d (5 GHz ch52, the one also broadcasting
        # ist_members) completes EAP but never answers DHCP: 0 leases in 54 tries over
        # 2026-10-15/16, while the campus a8:f7:d9:* APs lease at once. wpa_supplicant keeps
        # picking it for being 5 GHz and ignores a failed BSSID for only 10 s, so the laptop
        # ends up on the iPhone hotspot. NetworkManager has no BSSID denylist; dropping 5 GHz
        # is the way to keep away from it.
        band = "bg";
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

    # 0000UTokyo, the campus-only SSID. utelecon says it takes the same UTokyo Wi-Fi account
    # with the same PEAP/MSCHAPv2 settings, so this is the eduroam profile with the SSID swapped.
    profiles."0000utokyo" = {
      connection = {
        id = "0000UTokyo";
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        ssid = "0000UTokyo";
        mode = "infrastructure";
        band = "bg"; # same AP problem as eduroam above
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

    profiles.haus-5g-01 = {
      connection = {
        id = "Haus-5G-01";
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        ssid = "Haus-5G-01";
        mode = "infrastructure";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$HAUS_5G_01_PSK";
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
        # 2 = disable. The hotspot drops clients that doze through its beacons; see the TLP
        # WIFI_PWR_ON_BAT note in nixos-laptop.nix for why this alone is not enough on battery.
        powersave = 2;
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
