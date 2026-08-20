# 予約ページ (Calendly の代わり)。cal.com ではない。
#
# cal.com を入れなかった理由。あれは Next.js の monorepo に Postgres と Redis が付いて
# 来て、待ち受けているだけで 1〜1.5GB を持っていく。ここで欲しいのは「空いている時間を
# 公開して、他人に一枠取らせる」だけで、その値段は釣り合わない。Calnode は Go の単一
# バイナリと SQLite で、同じことを数十 MB でやる。だから他のスタックと違って DB
# コンテナが無い。
#
# 空き時間の判定は既にこの箱で動いている radicale から CalDAV で取る。連携先は環境
# 変数ではなく管理画面から app-password で登録する方式なので、ここには何も書かない。
# radicale 側に予約を書き戻すのも同じ接続でやる。
#
# タグを latest にしていないのは、まだ v0.2 系で日に何度もコミットが入る段階だから。
# `0.2` はパッチだけ追うので、破壊的変更が入った 0.3 が黙って降ってくることはない。
# 落ち着いたら他と揃えて latest でいい。
{
  lib,
  ...
}:

{
  # 新規サービスなので旧ホストから移ってくるデータが無い。bind mount の元を先に作る。
  #
  # 1階層だけにしてあるのは、この木の下では2階層目を tmpfiles が作れないため。
  # /var/lib/homelab 自体が uid 100000 (podman の userns root) 所有で、その下に
  # root 所有の calnode/ を作ったあと、さらにその中へ降りようとすると systemd が
  # 「Detected unsafe path transition /var/lib/homelab (owned by 100000) →
  # /var/lib/homelab/calnode (owned by root)」で拒否する。所有者が非 root から
  # root へ変わる経路を辿らせない安全策で、tmpfiles 側の設定では外せない。
  #
  # 実際 2026-08-20 の初回 rebuild で踏んだ。calnode/ はできるのに calnode/data/ が
  # できず、podman が `statfs /var/lib/homelab/calnode/data: no such file or
  # directory` で 125 を返して起動に失敗した (podman が自動で作るのは bind 先の
  # 直下1階層までで、入れ子は作らない)。
  #
  # なので data/ という階層をやめて、mount 元をこのディレクトリ自身にする。
  # readeck が同じ形で問題なく動いているのと揃う。
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/calnode 0700 root root -"
  ];

  virtualisation.oci-containers.containers."calnode" = {
    image = "ghcr.io/calnode/calnode:0.2";
    # CALNODE_ENCRYPTION_KEY と CALNODE_RECOVERY_SECRET。README.md を見ること。
    # BASE_URL が https なので、前者が無いとアプリは起動を拒否する。
    environmentFiles = [ "/var/lib/secrets/calnode.env" ];
    environment = {
      # スキーム込みで書く。https であること自体が本番モード (secure cookie と
      # 暗号鍵の強制) のスイッチになっている。
      "BASE_URL" = "https://cal.gapul.net";
      "DATABASE_URL" = "sqlite:///data/calnode.db";
      "PORT" = "3000";
    };
    volumes = [
      "/var/lib/homelab/calnode:/data:rw"
    ];
    # コンテナ側の 3000 は homepage が既に host 側で使っているので 8086 に出す。
    ports = [
      "8086:3000/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-calnode" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
