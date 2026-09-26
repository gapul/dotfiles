# Audiobookshelf — オーディオブックと電子書籍の棚 (books.gapul.net)。
#
# 接続してくるのは iPhone の 2 本。Audiobookshelf アプリ (自己ビルド、altstore-source の
# abs- タグ) は API を直接、Readest は /opds のカタログを読む。どちらもここの
# ユーザー名とパスワードでログインするので Authelia は挟まない (wger と同じ理由)。
#
# 実ファイルは /srv/audiobooks と /srv/books。他の /srv と同じく restic の対象外
# (買い直せる・取り直せるものに容量を使わない)。メタデータと再生位置は
# /var/lib/audiobookshelf で、こちらは /var/lib ごとバックアップに入る。
_: {
  services.audiobookshelf = {
    enable = true;
    host = "127.0.0.1";
    port = 8107;
  };

  # アプリからのアップロードも受けるので audiobookshelf ユーザーの所有にしておく。
  systemd.tmpfiles.rules = [
    "d /srv/audiobooks 0755 audiobookshelf audiobookshelf -"
    "d /srv/books 0755 audiobookshelf audiobookshelf -"
  ];
}
