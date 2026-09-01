# Bambu プリンタの操作盤 (Bambuddy)。スマホから「SD の中から選んで刷る」をやる先。
#
# 経緯。Bambu の Authorization Control で、サードパーティのスライサーから印刷を開始
# する経路が塞がれた。プリンタを LAN Only + Developer Mode にすればローカルからの制御
# は戻るが、代償に Bambu Handy が死ぬ — クラウド前提のアプリなので、同じ Wi-Fi にいて
# も繋がらない。Handy が持っていた「外から様子を見る」「ファイルを選んで刷る」の行き先
# がここになる。
#
# Home Assistant の ha-bambulab とは役割が違うので両方置く。あちらは監視と
# オートメーション側で、公開サービスは send_command 一つだけ、pybambu に FTP が無いので
# SD のファイル一覧が取れない。置く・選ぶ・消すはこちらが持つ。
#
# LAN-only 向けのファームウェア更新ヘルパーも入っている。公開済みの全バージョンに
# Usable / Unavailable / Installed のバッジが付くので、月一で見に行く先もここでいい
# (LAN Only の間は OTA が来ないので、更新作業そのものは microSD 経由の手作業)。
#
# bridge で動かす。上流の compose は host networking を既定にしているが、それは SSDP で
# プリンタを見つけるためで、この箱では 8000 も 3000 も既に埋まっている。プリンタは IP で
# 足せる (192.168.116.97) ので、discovery を捨てて衝突を避けるほうが得。仮想プリンタ機能
# (990 / 8883 / 322 / 50000-) も使わないから、開けるのは UI の 1 ポートだけでいい。
#
# 秘密は要らない。プリンタのアクセスコードは UI から入れてデータディレクトリの中に入る。
# rebuild の前に手で置くファイルは無い。
{
  lib,
  ...
}:

{
  # 新規サービスなので旧ホストから移ってくるデータが無い。bind mount の元を先に作る。
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/bambuddy 0700 root root -"
    "d /var/lib/homelab/bambuddy/data 0700 root root -"
    "d /var/lib/homelab/bambuddy/logs 0700 root root -"
  ];

  virtualisation.oci-containers.containers."bambuddy" = {
    # beta タグ (0.2.2b1 など) は latest にならない作りなので、latest は安定版を指す。
    # 他のスタックと揃えて latest でよい。
    image = "ghcr.io/maziggy/bambuddy:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
      # entrypoint が /app/data と /app/logs を chown してから gosu で降格する。
      # 既定の 1000:1000 だと root 所有の bind mount 元に書けないので、他のスタックと
      # 同じく root のまま走らせる。
      "PUID" = "0";
      "PGID" = "0";
      # host networking を前提にした変数だが、bridge でもコンテナ内の listen ポートを
      # 決めるので明示しておく。外向きは下の ports で 8010 に出す。
      "PORT" = "8000";
    };
    volumes = [
      "/var/lib/homelab/bambuddy/data:/app/data:rw"
      "/var/lib/homelab/bambuddy/logs:/app/logs:rw"
    ];
    ports = [
      "8010:8000/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-bambuddy" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
