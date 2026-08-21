{ config, ... }:
{
  # SOPS: decrypt encrypted secrets at home-manager switch time
  # (paths without ~/Library are OS-independent)
  #
  # Split out from common.nix (2026-07-19): so hosts without an age key (macmini)
  # can share common.nix. Only homeConfigurations that load the sops-nix module
  # (laptop / WSL / linux) import this file.
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    # common.yaml = what every machine needs. The mac-only half lives in secrets/darwin.yaml
    # (see secrets-darwin.nix), so a rebuild on the laptop or WSL no longer materialises an Apple ID
    # and a code-signing key that nothing there can use.
    #
    # Note on the host keys in .sops.yaml: they are recipients for the system-level sops that comes
    # next, not for this module. sops runs as the user here and /etc/ssh/ssh_host_ed25519_key is
    # 0600 root:wheel, so host-key decryption is only reachable from the nix-darwin / NixOS side.
    defaultSopsFile = ../../secrets/common.yaml;
    secrets = {
      "vpn/proton".path = "${config.home.homeDirectory}/.config/wireguard/proton.conf";
      "vpn/wgcf".path = "${config.home.homeDirectory}/.config/wireguard/wgcf-profile.conf";
      "rclone_conf".path = "${config.home.homeDirectory}/.config/rclone/rclone.conf";
      "ssh_config".path = "${config.home.homeDirectory}/.ssh/config";
      "ssh_authorized_keys".path = "${config.home.homeDirectory}/.ssh/authorized_keys";

      # attic (self-hosted nix binary cache at cache.gapul.net): the whole client config, because
      # the push token lives in it. Was a hand-written plaintext file until 2026-08.
      "attic_config".path = "${config.home.homeDirectory}/.config/attic/config.toml";

      # PII single source
      "pii/name" = { };
      "pii/email_personal" = { };
      "pii/email_school" = { };
      "pii/email_work" = { };
      "pii/birthday" = { };
      "pii/gmail_app_password_mail" = { };
      "pii/gmail_app_password_caldav" = { };
    };

    # aerc / calcurse templates are OS-independent (`~/.config/...`)
    templates = {
      "aerc-accounts.conf" = {
        path = "${config.home.homeDirectory}/.config/aerc/accounts.conf";
        content = ''
          [Gmail]
          source = imaps://${config.sops.placeholder."pii/email_personal"}@imap.gmail.com:993
          source-cred-cmd = echo "${config.sops.placeholder."pii/gmail_app_password_mail"}"
          outgoing = smtps+plain://${config.sops.placeholder."pii/email_personal"}@smtp.gmail.com:465
          outgoing-cred-cmd = echo "${config.sops.placeholder."pii/gmail_app_password_mail"}"
          from = ${config.sops.placeholder."pii/name"} <${config.sops.placeholder."pii/email_personal"}>
          copy-to = Sent
        '';
      };

      "calcurse-caldav-config" = {
        path = "${config.home.homeDirectory}/.config/calcurse/caldav/config";
        content = ''
          [General]
          SyncDir = ~/.local/share/calcurse/
          SpawnEditor = vi

          [CalDAV]
          ServerAddress = www.google.com
          ServerPort = 443
          ServerPath = /calendar/dav/${config.sops.placeholder."pii/email_personal"}/events/
          InsecureSSL = No
          Verbose = Yes

          [Auth]
          Username = ${config.sops.placeholder."pii/email_personal"}
          Password = ${config.sops.placeholder."pii/gmail_app_password_caldav"}
        '';
      };
      "nvim-birthday.lua" = {
        path = "${config.home.homeDirectory}/.config/nvim-private/birthday.lua";
        mode = "0400";
        content = ''
          return {
            name = ${builtins.toJSON config.sops.placeholder."pii/name"},
            birthday = ${builtins.toJSON config.sops.placeholder."pii/birthday"},
            palette = "dusty",
          }
        '';
      };
    };
  };
}
