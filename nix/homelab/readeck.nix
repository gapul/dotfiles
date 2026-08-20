# 後で読む (Pocket の代わり)。
#
# 既にあるものとの棲み分け。archivebox は「消える前に丸ごと保存する」ためのもので、
# 読むための道具ではない。miniflux は購読で、読み終わったら流れていく。その二つの
# 間に「あとで腰を据えて読む」が無かった。readeck はそこだけを埋める。
#
# 選定理由は軽さ。karakeep のほうが AI タグ付けやネイティブアプリがあって機能は上だが、
# Next.js に meilisearch とヘッドレス Chrome が付いてくる。readeck は Go の単一
# バイナリと SQLite なので、この箱で一番小さい部類に収まる。空きメモリが 6.5GB しか
# 無いところに calnode も入れるので、ここは軽いほうを取った。
#
# miniflux 2.3.3 は readeck を統合先として最初から知っている (binary に wallabag /
# linkding / shiori / karakeep と並んで入っているのを確認した)。購読で見つけたものを
# その場で放り込めるので、二つを別々に使うより噛み合う。連携の設定は miniflux 側の
# UI から readeck の URL と API トークンを入れる作業で、宣言できるものではない。
#
# 秘密は要らない。secret key は初回起動時に自前で生成してデータディレクトリに置く
# (0.23.1 の "Use generated secret key during first run")。管理ユーザも初回に
# ブラウザから作る。つまり rebuild 前に手で置くファイルは無い。
{
  lib,
  ...
}:

{
  # 新規サービスなので旧ホストから移ってくるデータが無い。bind mount の元を先に作る。
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/readeck 0700 root root -"
  ];

  virtualisation.oci-containers.containers."readeck" = {
    # Docker Hub ではなく Codeberg のレジストリ。0.23 系で安定しているので、
    # 他のスタックと揃えて latest でよい (calnode を 0.2 に固定したのは、あちらが
    # まだ v0.2 系で日に何度もコミットが入るため。ここは事情が違う)。
    image = "codeberg.org/readeck/readeck:latest";
    environment = {
      # HOST はイメージ側で既に 0.0.0.0 になっているので念押し。PORT のほうは
      # イメージが空文字を入れており (podman image inspect で確認)、ここで
      # 与えないと既定値の解釈に委ねることになるので明示する。
      "READECK_SERVER_HOST" = "0.0.0.0";
      "READECK_SERVER_PORT" = "8000";
      # Caddy 越しなので、名乗ってくる Host を明示的に許す必要がある。
      "READECK_ALLOWED_HOSTS" = "read.gapul.net";
      "READECK_USE_X_FORWARDED" = "1";
      # journald に流すので、JSON より読める形のほうがいい。
      "READECK_LOG_FORMAT" = "text";
    };
    volumes = [
      "/var/lib/homelab/readeck:/readeck:rw"
    ];
    ports = [
      "8087:8000/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-readeck" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
