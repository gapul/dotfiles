{ config, ... }:
# eduroam with the UTokyo Wi-Fi account. Settings follow utelecon's Android guide
# (https://utelecon.adm.u-tokyo.ac.jp/utokyo_wifi/android/): PEAP + MSCHAPv2, system CA store,
# domain u-tokyo.ac.jp. The anonymous outer identity keeps the user ID out of the clear-text
# EAP exchange (the same realm the iwd example by haxibami uses).
#
# The ID and password live in secrets/nixos-laptop.yaml as one env file, decrypted at boot by
# sops-nix with this machine's SSH host key; NetworkManager substitutes $EDUROAM_* into the
# profile when ensure-profiles runs. Single-quote the password there: it contains '#' and '&'.
{
  sops.defaultSopsFile = ../../secrets/nixos-laptop.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.eduroam_env = { };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.secrets.eduroam_env.path ];
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
  };
}
