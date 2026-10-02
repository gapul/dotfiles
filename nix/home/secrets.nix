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
      # ed25519 key dedicated to unattended jobs. The everyday key lives in the Secure Enclave and
      # needs Touch ID approval for every signature, so when the approval window lapses, automatic
      # deploys and scheduled jobs silently stop (2026-08-30). Making a second Secure Enclave key
      # without biometrics was tried the same day and is blocked (Apple's provider cannot register
      # sk keys, #499).
      #
      # It is a file, so there is no enclave guarantee. To compensate, ssh_config limits its
      # destinations to homeserver and macmini, and it can be revoked on its own.
      "ssh_automation_key" = {
        path = "${config.home.homeDirectory}/.ssh/id_automation";
        mode = "0600";
      };
      # The work machine alone gets a separate key. The work machine's authorized_keys is owned by
      # us and writable (confirmed 2026-08-30; "cannot re-register" was an outdated note). The key
      # was made for mutagen sync; after mutagen was retired, ssh_config's mvrx-nolang-dev uses it.
      # Of the keys the main Mac holds, the work machine accepts this one and the enclave key, and
      # id_automation is not on it (confirmed 2026-09-16 by fingerprint and -F /dev/null tests).
      # The work machine's own list has 4 keys. Details in the notes in nix/keys/authorized_keys.
      #
      # Do not reuse ssh_automation_key. If home and work privileges are mixed into one key,
      # revoking either takes both down. Wanting to cut only the work side is the likelier case,
      # so the boundary is drawn here.
      "ssh_mvrx_sync_key" = {
        path = "${config.home.homeDirectory}/.ssh/id_mvrx_sync";
        mode = "0600";
      };
      # "ssh_authorized_keys" is no longer placed here: modules/authorized-keys.nix declares the
      # same keys for every host from nix/keys/authorized_keys, so writing a second copy into
      # ~/.ssh/authorized_keys would just be a rival source that drifts. The value is still in
      # secrets/common.yaml, unused, until this is confirmed working on a real rebuild.

      # attic (self-hosted nix binary cache at cache.gapul.net): the whole client config, because
      # the push token lives in it. Was a hand-written plaintext file until 2026-08.
      "attic_config".path = "${config.home.homeDirectory}/.config/attic/config.toml";
      # Same as the htpasswd of the home Radicale (dav.gapul.net). Calendars, tasks and contacts
      # were consolidated there, so calcurse's caldav config reads this. The server is a host
      # without sops, so this is managed as a pair with the bcrypt hand-placed in
      # /var/lib/homelab/radicale/config/users. Workstations read it, so it lives in common.yaml
      # rather than homelab.yaml.
      "radicale/username" = { };
      "radicale/password" = { };

      # atuin's E2E encryption key. Without it, synced history cannot be decrypted.
      #
      # Why here and not in Bitwarden: it is not something a human types, but a file atuin reads
      # from a fixed path. Keeping it in sops means a new machine materialises it in the right
      # place with just a rebuild, and the manual copy step goes away.
      # (What Bitwarden needs is atuin's **password**, which a human types at login. A different
      #  thing.)
      #
      # With mode 0400, atuin login fails trying to write it back, hence 0600. sops is the source
      # of truth, though, so if login writes a different key, the next activation restores it.
      # To change the key, update secrets/common.yaml.
      "atuin/key" = {
        path = "${config.home.homeDirectory}/.local/share/atuin/key";
        mode = "0600";
      };
      # atuin's password, used by `atuin login`. Unlike the key it is not read as a file, so no
      # path is set and it goes in sops' default location (the /run/... equivalent).
      # Keeping it in Bitwarden too means it can be typed by hand when the main Mac is broken.
      "atuin/password" = { };

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
          # 宛先は自宅の Radicale(gapul/calendar)。Google カレンダーから移した。
          # dav.gapul.net は Caddy が ACME 証明書で終端していて、A レコードは tailnet を
          # 指しているので、tailnet の外からは名前が引けても届かない。
          #
          # キー名に注意: 以前の書式(General の同期ディレクトリ指定、CalDAV セクションの
          # サーバ指定)はいまの calcurse-caldav が受け付けず、起動即エラーになる。
          # 正しくは [General] の Hostname / Path / HTTPS。
          # なおコメント行も設定として読まれるので、旧キー名をここに書いてはいけない。
          [General]
          Binary = calcurse
          # 既定は DryRun = Yes。明示しないと接続だけして何も同期しない。
          DryRun = No
          Hostname = dav.gapul.net
          Path = /gapul/calendar/
          HTTPS = Yes
          InsecureSSL = No
          Verbose = Yes

          [Auth]
          Username = ${config.sops.placeholder."radicale/username"}
          Password = ${config.sops.placeholder."radicale/password"}
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
