# 統合カレンダー配信 (Google/iCloud/自宅Radicale/任意の.ics を1本のフィードにまとめる)。
# 元は Cloudflare Worker だったが、個人の予定を Google Calendar から自宅 Radicale へ
# 移した (radicale.nix) のに合わせて homeserver 内部で完結させる方針に変えた。
# Radicale(127.0.0.1:5232)はコンテナ間ネットワーク越しに直接叩けるので、外に晒す必要がない。
#
# ソース: gapul/unified-calendar(private)。push → main で GitHub Actions が
# ghcr.io/gapul/unified-calendar:latest を焼く。Secret はコードに置かず、
# 他のスタックと同じく /var/lib/secrets/unified-calendar.env を環境変数として渡す
# (中身は secrets.nix 経由で sops-nix が homelab.yaml の homeserver_files/unified-calendar.env
# から復元する)。
{
  lib,
  ...
}:

{
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/unified-calendar 0700 root root -"
  ];

  virtualisation.oci-containers.containers."unified-calendar" = {
    image = "ghcr.io/gapul/unified-calendar:latest";
    environmentFiles = [ "/var/lib/secrets/unified-calendar.env" ];
    environment = {
      "PORT" = "8080";
      "DATA_DIR" = "/data";
    };
    volumes = [
      "/var/lib/homelab/unified-calendar:/data:rw"
    ];
    ports = [
      "8113:8080/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-unified-calendar" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
