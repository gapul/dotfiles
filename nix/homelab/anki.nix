# Anki の同期サーバ。AnkiWeb に預けず自前で持つ。
#
# クライアントは iOS の amgi (FOSS フォーク) と母艦の Anki 本体。Anki 本体が
# 同梱している rslib のサーバをそのまま使うので、追加の実装もリバースエンジニア
# リングも要らない。同期プロトコルは素の HTTP なので、他と同じ caddy の vhost で足りる。
#
# パスワードは他の秘密と同じく手で置く (/var/lib/secrets/anki-sync.password)。
# 中身は平文1行で、モジュールがそれを読んでユーザーを作る。
{
  services.anki-sync-server = {
    enable = true;
    # caddy 経由でしか出さないので loopback に閉じる。tailnet 直叩きもさせない。
    address = "127.0.0.1";
    port = 27701;
    openFirewall = false;
    users = [
      {
        username = "gapul";
        passwordFile = "/var/lib/secrets/anki-sync.password";
      }
    ];
  };
}
