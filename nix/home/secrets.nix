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
      # 自宅 Radicale(dav.gapul.net)の htpasswd と同じもの。カレンダー・タスク・連絡先を
      # ここへ集約したので、calcurse の caldav 設定がこれを読む。サーバ側は sops を持たない
      # ホストなので /var/lib/homelab/radicale/config/users に手置きした bcrypt と対で管理する。
      # ワークステーションが読むので homelab.yaml ではなく common.yaml 側に置いてある。
      "radicale/username" = { };
      "radicale/password" = { };

      # atuin の E2E 暗号鍵。これが無いと同期した履歴を復号できない。
      #
      # Bitwarden ではなくここに置く理由: 人間が打つものではなく、atuin が決まった
      # パスから読むファイルだから。sops に載せておけば新しい端末でも rebuild だけで
      # 正しい場所に materialise される。手でコピーする手順が消える。
      # (Bitwarden 側に要るのは atuin の**パスワード**のほうで、あれは login のときに
      #  人間が打つもの。別物。)
      #
      # mode が 0400 だと atuin login が書き戻そうとして失敗するので 0600。ただし
      # sops が正なので、login が別の鍵を書いても次の activation で戻る。鍵を
      # 変えるときは secrets/common.yaml を更新すること。
      "atuin/key" = {
        path = "${config.home.homeDirectory}/.local/share/atuin/key";
        mode = "0600";
      };
      # atuin のパスワード。`atuin login` で使う。鍵と違ってファイルとして読まれる
      # ものではないので path は指定せず、sops の既定の場所 (/run/... 相当) に置く。
      # Bitwarden にも入れておくと、母艦が壊れているときに手で打てる。
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
