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
    defaultSopsFile = ../../secrets/secrets.yaml;
    secrets = {
      "vpn/proton".path = "${config.home.homeDirectory}/.config/wireguard/proton.conf";
      "vpn/wgcf".path = "${config.home.homeDirectory}/.config/wireguard/wgcf-profile.conf";
      "rclone_conf".path = "${config.home.homeDirectory}/.config/rclone/rclone.conf";
      "ssh_config".path = "${config.home.homeDirectory}/.ssh/config";
      "ssh_authorized_keys".path = "${config.home.homeDirectory}/.ssh/authorized_keys";

      # Apple ID for xcodes' Xcode downloads. `just upgrade` reads these files into
      # XCODES_USERNAME / XCODES_PASSWORD so username+password auth is non-interactive;
      # 2FA is still prompted the first time and when Apple's cached session expires.
      "xcodes/apple_id".path = "${config.home.homeDirectory}/.config/xcodes/apple_id";
      "xcodes/password".path = "${config.home.homeDirectory}/.config/xcodes/password";

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
