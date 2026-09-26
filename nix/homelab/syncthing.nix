{
  # Syncthing, the one service whose whole configuration used to live in a web UI.
  # Devices and folders are declared here; the module reconciles them on start, so
  # pairing a new machine is a commit rather than a session of clicking.
  #
  # Device IDs are public keys, safe to commit. What must NOT be recreated is this
  # node's own identity in /var/lib/syncthing (cert.pem, key.pem): losing it gives
  # the host a new device ID and the Mac would have to re-accept it and rescan the
  # whole folder. That directory is part of the data to migrate, not something to
  # regenerate.
  # 同期先の所有者を syncthing に固定する。移行直後は /srv/syncthing が uid 101000
  # (旧 CT101 の rootless コンテナ時代の subuid) のままで、ネイティブの syncthing
  # (uid 237) が自分のフォルダに書き込めなかった。Mac とは接続できているのに
  # SyncHub が .stfolder だけの空、という形で 2026-08-16 まで気付かれていない。
  systemd.tmpfiles.rules = [
    "d /srv/syncthing 0755 syncthing syncthing -"
    "Z /srv/syncthing - syncthing syncthing -"
    # Paperless inbox (folder below). Syncthing (uid 237) writes here and the paperless container
    # (uid 1000, no userns) deletes each file once consumed, so both need write on the directory.
    # Files arrive 0644, readable by paperless; the directory is the only thing opened up.
    "d /var/lib/homelab/paperless/consume 0777 1000 1000 -"
  ];

  services.syncthing = {
    enable = true;
    # The old container ran GUI on 8384 and sync on 22000, fronted at
    # sync.gapul.net; keep the numbers so the caddy vhost and the Mac's configured
    # address both still fit.
    guiAddress = "127.0.0.1:8384";
    openDefaultPorts = true;
    settings = {
      devices."macbook-mini".id = "3YUCLFD-KVCQOP4-KF4CPIA-MA5EDJH-QO6NQ7V-CHH3LVZ-GQTNFQZ-A4LEWQ2";
      # iPhone は Synctrain (iOS の Syncthing クライアント)。ID はアプリの Start 画面の
      # "This device's identifier" から読んだもの。公開鍵なので commit してよい。
      devices."iphone" = {
        id = "R3V5V7Y-ZRBHIHY-F35M3PX-4H3I73G-4UA7UHT-CH523JH-O37RSW3-PNLJPAX";
        # モバイル回線でも中継越しに繋がるようにしておく。tailnet 内なら直結する。
        introducer = false;
      };
      # 個人の記録の集約先。端末ごとに <ホスト名>/ を掘って、各端末は自分の
      # ディレクトリしか書かない。同じファイルを複数の端末が書くことがないので、
      # 構造として競合が起きない (home/personal-history.nix 参照)。
      # iPhone には配らない。読むのは母艦と macmini だけで、量も多い。
      folders."personal-history" = {
        label = "Personal History";
        path = "/srv/syncthing/personal-history";
        devices = [ "macbook-mini" ];
        type = "sendreceive";
      };
      # Drop a PDF on the Mac or save a scan on the iPhone and Paperless consumes it. This side is
      # Paperless' consume directory itself: consumed files are deleted, and sendreceive carries
      # the deletion back, so an emptied inbox is the confirmation. Syncthing's .stfolder and
      # temp files are in Paperless' default ignore list.
      folders."paperless-inbox" = {
        label = "Paperless Inbox";
        path = "/var/lib/homelab/paperless/consume";
        devices = [
          "macbook-mini"
          "iphone"
        ];
        type = "sendreceive";
      };
      # Obsidian の vault。中身の同期は LiveSync (obsidian-couchdb.nix) の仕事で、
      # こちらは履歴を取るためだけの片方向の複製: 母艦が送り、ここは受けるだけ
      # (receiveonly)。書き手が一人なので LiveSync と取り合いにならない。
      # コミットは vault-git.nix の毎時タイマー。
      folders."obsidian-vault" = {
        label = "Obsidian Vault";
        path = "/srv/syncthing/obsidian-vault";
        devices = [ "macbook-mini" ];
        type = "receiveonly";
        # 母艦の vault のファイルは 0600 で、そのまま複製されると vault-git ユーザー
        # (syncthing グループに入れてある) が読めず、初回の commit が
        # "open(.gitignore): Permission denied" で落ちた。パーミッションを運ばせない
        # と syncthing 自身の umask で 0644 になる。送る側も同じ設定にしてある。
        ignorePerms = true;
      };
      folders."synchub" = {
        label = "SyncHub";
        # Was /mnt/jellyfin-media/syncthing/SyncHub on the old host, mounted into
        # the container as /data/SyncHub.
        path = "/srv/syncthing/SyncHub";
        devices = [
          "macbook-mini"
          "iphone"
        ];
        type = "sendreceive";
      };
    };
  };
}
