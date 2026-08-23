# RomM — ROM のライブラリ。Jellyfin と同じ発想で、棚に並んだものを
# ブラウザから見て、そのまま遊べる (EmulatorJS がブラウザ内で動く)。
#
# なぜ ROM だけ別建てかというと、PC ゲームと性質が違うから。ROM は 1 ファイル
# 1 タイトルで、メタデータを外部 (IGDB) から引いて初めて棚になる。PC ゲームは
# インストーラの塊で、必要なのは置き場所と目録だけ。同じ道具で両方やろうとすると
# どちらも中途半端になる。PC 側は gameyfin.nix。
#
# 実ファイルは /srv/games/roms。大容量ディスク側で、restic の対象外。
# 吸い出し直せるものにバックアップ容量を使わない、という他の /srv と同じ判断。
{
  pkgs,
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."romm-db" = {
    image = "docker.io/library/mariadb:11";
    environment = {
      "MARIADB_DATABASE" = "romm";
      "MARIADB_USER" = "romm";
    };
    # MARIADB_ROOT_PASSWORD と MARIADB_PASSWORD は romm.env から。
    environmentFiles = [ "/var/lib/secrets/romm.env" ];
    volumes = [
      "/var/lib/homelab/romm/db:/var/lib/mysql:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=romm-db"
      "--network=romm_default"
      "--health-cmd=healthcheck.sh --connect --innodb_initialized"
      "--health-interval=10s"
      "--health-retries=5"
    ];
  };
  systemd.services."podman-romm-db" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-romm_default.service" ];
    requires = [ "podman-network-romm_default.service" ];
    partOf = [ "podman-compose-romm-root.target" ];
    wantedBy = [ "podman-compose-romm-root.target" ];
  };

  virtualisation.oci-containers.containers."romm" = {
    image = "docker.io/rommapp/romm:latest";
    environment = {
      "DB_HOST" = "romm-db";
      "DB_NAME" = "romm";
      "DB_USER" = "romm";
    };
    # DB_PASSWD / ROMM_AUTH_SECRET_KEY / IGDB_CLIENT_ID / IGDB_CLIENT_SECRET。
    # IGDB の 2 つが無いとメタデータが引けず、棚がファイル名の羅列になる。
    environmentFiles = [ "/var/lib/secrets/romm.env" ];
    volumes = [
      "/var/lib/homelab/romm/resources:/romm/resources:rw" # 取得したカバー画像
      "/var/lib/homelab/romm/redis:/redis-data:rw"
      "/srv/games/roms:/romm/library:rw"
      "/srv/games/roms-assets:/romm/assets:rw" # セーブデータ・ステート
    ];
    ports = [ "8091:8080/tcp" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=romm"
      "--network=romm_default"
    ];
    dependsOn = [ "romm-db" ];
  };
  systemd.services."podman-romm" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-romm_default.service" ];
    requires = [ "podman-network-romm_default.service" ];
    partOf = [ "podman-compose-romm-root.target" ];
    wantedBy = [ "podman-compose-romm-root.target" ];
  };

  systemd.services."podman-network-romm_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f romm_default";
    };
    script = ''
      podman network inspect romm_default || podman network create romm_default
    '';
    partOf = [ "podman-compose-romm-root.target" ];
    wantedBy = [ "podman-compose-romm-root.target" ];
  };

  systemd.targets."podman-compose-romm-root" = {
    unitConfig.Description = "romm (ROM ライブラリ)";
    wantedBy = [ "multi-user.target" ];
  };

  # RomM はプラットフォームごとの下位ディレクトリを見る (roms/gb, roms/snes, ...)。
  # 空でも作っておかないと、最初のスキャンが「ライブラリが無い」で終わる。
  systemd.tmpfiles.rules = [
    # podman は bind mount の元を作らない (docker と違うところ)。無いまま起動すると
    # `statfs ...: no such file or directory` で 125 を返し、restart を繰り返して
    # start-limit-hit で止まる。
    "d /var/lib/homelab/romm 0700 root root -"
    "d /var/lib/homelab/romm/db 0700 root root -"
    "d /var/lib/homelab/romm/resources 0700 root root -"
    "d /var/lib/homelab/romm/redis 0700 root root -"
    "d /srv/games 0755 root root -"
    "d /srv/games/roms 0755 root root -"
    "d /srv/games/roms-assets 0755 root root -"
  ];
}
