# 日程調整 (調整さん / Doodle の代わり)。サークル用なので tailnet の外から開ける。
#
# calnode との棲み分け。あちらは予約で、こちらは投票。予約は「公開した空き枠を
# 誰か1人が取り、取られた枠は消える」排他的な仕組みで、日程調整は「候補日を並べて
# 全員が全部に○×を付け、重なりを探す」非排他的な仕組み。前者で後者はできない
# (1人が押さえた瞬間、他の人が同じ日に丸を付けられなくなる)。calnode の機能一覧に
# 投票や集計に相当するものは無い。別のサービスが要る、という結論。
#
# 参加者はアカウント不要でゲストのまま投票できる。作成側もゲストで作れるので、
# SMTP が無くても最低限は回る。ログインしてポールを管理したくなったら、そのとき
# SMTP を足す (SMTP_* を rallly.env に置くだけ)。
#
# タグを latest にしていないのは、Next.js + Prisma で DB マイグレーションが走る
# 構造だから。`4` はメジャー内の更新だけ追うので、5 系が黙って降ってきて migration
# が片道で走る事故を避けられる。
{
  pkgs,
  lib,
  ...
}:

{
  # bind mount の元。**1階層だけ**にしてある。/var/lib/homelab 自体が uid 100000
  # (podman の userns root) 所有なので、その下に root 所有のディレクトリを作った
  # 後さらに中へ降りると systemd が unsafe path transition で拒否する。calnode で
  # 実際に踏んだ (詳細は calnode.nix)。なので db 用は入れ子にせず並べる。
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/rallly-db 0700 root root -"
  ];

  virtualisation.oci-containers.containers."rallly" = {
    # Docker Hub だが、hosts/homeserver.nix が docker.io を mirror.gcr.io へ
    # 差し替えているので pull 制限には当たらない。
    image = "docker.io/lukevella/rallly:4";
    # DATABASE_URL / SECRET_PASSWORD / SUPPORT_EMAIL。README.md を見ること。
    # SECRET_PASSWORD は 32 文字以上でないとアプリが起動時に弾く (zod で検証している)。
    environmentFiles = [ "/var/lib/secrets/rallly.env" ];
    environment = {
      # 自己ホストではこれを実行時に読む。ビルド時ではない。
      "NEXT_PUBLIC_BASE_URL" = "https://poll.gapul.net";
    };
    ports = [
      "8089:3000/tcp"
    ];
    dependsOn = [ "rallly-db" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=rallly"
      "--network=rallly_default"
    ];
  };
  systemd.services."podman-rallly" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-rallly_default.service" ];
    requires = [ "podman-network-rallly_default.service" ];
  };

  virtualisation.oci-containers.containers."rallly-db" = {
    # 上流の compose が指定しているのがこれ。18 系は PGDATA の位置が変わっているが、
    # 親ディレクトリごと mount するので気にしなくてよい (上流も同じことをしている)。
    image = "postgres:18-alpine";
    environmentFiles = [ "/var/lib/secrets/rallly.env" ];
    environment = {
      "POSTGRES_DB" = "rallly";
      "POSTGRES_USER" = "rallly";
    };
    volumes = [
      "/var/lib/homelab/rallly-db:/var/lib/postgresql:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=[\"pg_isready\", \"-U\", \"rallly\"]"
      "--health-interval=10s"
      "--health-retries=5"
      "--health-timeout=5s"
      "--network-alias=db"
      "--network=rallly_default"
    ];
  };
  systemd.services."podman-rallly-db" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-rallly_default.service" ];
    requires = [ "podman-network-rallly_default.service" ];
  };

  systemd.services."podman-network-rallly_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f rallly_default";
    };
    script = ''
      podman network inspect rallly_default || podman network create rallly_default
    '';
    wantedBy = [ "multi-user.target" ];
  };
}
