# 割り勘 (walica / Splitwise の代わり)。相手がいる用途なので tailnet の外に出す。
#
# 認証が無い。グループは URL を知っている人だけが開ける方式で、walica の
# 「アカウント不要、リンクを共有」と同じ考え方。つまりログインの仕組みも
# SMTP も要らず、動かすのに必要なのは DB だけ。
#
# 画像添付とレシートの読み取り (OpenAI) は既定で無効のまま。前者は S3 が要り、
# 後者は外部の API に領収書を投げることになる。どちらも今は要らない。
{
  pkgs,
  lib,
  ...
}:

{
  # rallly.nix と同じ理由で1階層。/var/lib/homelab の下に入れ子を作ろうとすると
  # tmpfiles が unsafe path transition で拒否する (calnode.nix 参照)。
  #
  # 所有者が root ではなく 70 なのは、postgres のイメージが uid 70 で動くため。
  # root 所有の 0700 だと `mkdir: can't create directory '/var/lib/postgresql/18/':
  # Permission denied` で起動に失敗する。既存の miniflux/db も uid 70 所有。
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/spliit-db 0700 70 70 -"
  ];

  virtualisation.oci-containers.containers."spliit" = {
    image = "ghcr.io/spliit-app/spliit:latest";
    # POSTGRES_PRISMA_URL と POSTGRES_URL_NON_POOLING。どちらもパスワードを
    # 含む接続文字列なので env ファイル側。README.md を見ること。
    environmentFiles = [ "/var/lib/secrets/spliit.env" ];
    environment = {
      "BASE_URL" = "https://split.gapul.net";
      # 円建てで使うので既定通貨を JPY にしておく。グループごとに変更できる。
      "DEFAULT_CURRENCY_CODE" = "JPY";
    };
    ports = [
      "8090:3000/tcp"
    ];
    dependsOn = [ "spliit-db" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=spliit"
      "--network=spliit_default"
    ];
  };
  systemd.services."podman-spliit" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-spliit_default.service" ];
    requires = [ "podman-network-spliit_default.service" ];
  };

  virtualisation.oci-containers.containers."spliit-db" = {
    image = "docker.io/library/postgres:18-alpine";
    environmentFiles = [ "/var/lib/secrets/spliit.env" ];
    environment = {
      "POSTGRES_DB" = "spliit";
      "POSTGRES_USER" = "spliit";
    };
    volumes = [
      "/var/lib/homelab/spliit-db:/var/lib/postgresql:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=[\"pg_isready\", \"-U\", \"spliit\"]"
      "--health-interval=10s"
      "--health-retries=5"
      "--health-timeout=5s"
      "--network-alias=db"
      "--network=spliit_default"
    ];
  };
  systemd.services."podman-spliit-db" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-spliit_default.service" ];
    requires = [ "podman-network-spliit_default.service" ];
  };

  systemd.services."podman-network-spliit_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f spliit_default";
    };
    script = ''
      podman network inspect spliit_default || podman network create spliit_default
    '';
    wantedBy = [ "multi-user.target" ];
  };
}
