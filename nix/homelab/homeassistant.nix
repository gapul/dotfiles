{
  # What replaces the HAOS VM. Home Assistant itself stays the official image so
  # the config directory, HACS and the update cadence carry over unchanged; the
  # five add-ons it used to run become either their own container or a native
  # service, since Supervisor does not exist outside HAOS.
  #
  # What is genuinely lost with Supervisor: the Apps store, one-click updates and
  # the built-in backup. The first two are replaced by this file, the third by
  # backup.nix — but take one `ha backups new` on the old machine before the swap,
  # because that is the last time that button exists.
  virtualisation.oci-containers.containers = {
    homeassistant = {
      image = "ghcr.io/home-assistant/home-assistant:stable";
      volumes = [
        "/var/lib/hass:/config:rw"
        "/etc/localtime:/etc/localtime:ro"
      ];
      environment.TZ = "Asia/Tokyo";
      # Host networking is not optional: discovery of ESPHome nodes and Matter
      # devices is mDNS, which does not cross a bridge.
      #
      # HAOS ran Home Assistant as root on the host, so two of default_config's
      # discovery paths worked without anyone declaring anything. In a container
      # they need the capabilities named explicitly: bluetooth talks to hci0
      # through a raw HCI socket, and the dhcp integration sniffs DHCP with a
      # packet socket. Without them the box has an adapter (hci0 is present and
      # unblocked) that Home Assistant cannot manage, and both log an error every
      # start.
      #
      # habluetooth (6.26.5 で確認) は起動ごとに "Missing NET_ADMIN/NET_RAW
      # capabilities for Bluetooth management" を出すが、これは上流の誤検知で、
      # ここを直す必要はない。2026-08-30 に中から測った結果:
      #   CapEff = 0x800435fb → NET_ADMIN も NET_RAW も立っている
      #   AF_BLUETOOTH の raw ソケットも管理チャネル (HCI_CHANNEL_CONTROL) も開ける
      # Bluetooth 自体は動いている。このログを見て capability を足しに来ないこと。
      extraOptions = [
        "--network=host"
        "--cap-add=NET_ADMIN"
        "--cap-add=NET_RAW"
      ];
      log-driver = "journald";
    };

    # The Matter add-on was this same image. Note what it is NOT: nixpkgs has
    # python-matter-server at 8.1.2 while the running add-on is 9.0.3, and the
    # server refuses storage written by a newer schema — using the module would
    # mean re-commissioning every Matter device.
    #
    # /var/lib/matter-server is the fabric. Copy it from the old machine
    # (supervisor/apps/data/core_matter_server, 8MB) and nothing needs re-pairing;
    # lose it and every device has to be factory reset.
    matter-server = {
      image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
      volumes = [ "/var/lib/matter-server:/data:rw" ];
      # Matter mandates IPv6 even for Wi-Fi devices, and commissioning needs mDNS.
      # If this host has IPv6 disabled the server starts happily and every device
      # then sits there unavailable, which is the least obvious way this can fail.
      extraOptions = [ "--network=host" ];
      log-driver = "journald";
    };
  };

  # --- the add-ons that became services ---

  # The add-on authenticated MQTT clients against Home Assistant's own user
  # accounts, which has no equivalent here: the user is declared and its password
  # hash (mosquitto_passwd format) is placed by hand. Every client has to be
  # updated with the new credential.
  #
  # It listens on all interfaces as the add-on did, but the firewall only trusts
  # tailscale0, so in practice that means localhost and the tailnet. A sensor
  # publishing from the LAN would need 1883 opened.
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "0.0.0.0";
        port = 1883;
        users.ha = {
          acl = [ "readwrite #" ];
          hashedPasswordFile = "/var/lib/secrets/mosquitto-ha.password";
        };
      }
    ];
  };

  # ESPHome のダッシュボードは止めてある (2026-08-31)。
  #
  # 上流が本体からダッシュボードを削除し、esphome-device-builder という別パッケージに
  # なった。nixpkgs のモジュールはまだ `esphome dashboard` を叩くので、起動するたびに
  #
  #   ERROR The built-in dashboard has been removed from ESPHome.
  #
  # で落ちて再起動を繰り返す。nixpkgs 側は対応中 (NixOS/nixpkgs#550245
  # "nixos/esphome: convert to new device builder")。
  #
  # 止めても失うものは無い。移行のときに /var/lib/esphome へ yaml を持ってくる想定で
  # 宣言したが、実際には Home Assistant の config 側 (data/esphome) に残ったままで、
  # ここは空だった (2026-08-31 に確認: yaml 0 件)。何も提供していないサービスが
  # 落ちていただけ。
  #
  # 版を古いところで固定する手もあったが採らない。ローリングに移した方針に反するうえ、
  # 書き込み機に対して更新を止める形になる。上流の PR が入ったら enable に戻す。
  services.esphome.enable = false;

  services.node-red = {
    enable = true;
    port = 1880;
    # The add-on installs palette nodes at runtime through npm, which needs a
    # compiler present or the install fails halfway through.
    withNpmAndGcc = true;
  };
}
