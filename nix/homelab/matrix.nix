# Conduit は nixpkgs のモジュールで直接動かす。残りのブリッジだけ compose2nix 由来の
# コンテナのまま。元は /opt/stacks/matrix/compose.yaml 全体をコンテナ化したものだった。
#
# ブリッジをモジュール化しなかった理由 (2026-08-11 に調べた結果):
#   - services.mautrix-telegram の nixpkgs パッケージは Python 版 0.15.3 で、動いているのは
#     Go 版 (bridgev2)。SQLite のスキーマが別物なので、載せ替えると portal/puppet が消える。
#   - services.mautrix-discord は Go 版で一致するが、モジュールは起動ごとに
#     `--generate-registration` を走らせる。これは sender_localpart を作り直す (実測)。
#     Synapse なら登録ファイルを読み直すので揃うが、Conduit は登録を RocksDB に持ち
#     admin room 経由でしか変えられないため、起動ごとに片側だけずれていく。
#   - config.yaml はブリッジの DB と不可分で、どちらも restic に入っている。nix で宣言し直す
#     旨みが薄い割に、トークンを外に出すテンプレート層が2つ増える。
{
  pkgs,
  lib,
  ...
}:

{
  # Conduit 0.10.12。コンテナも同じ 0.10.12 だったので RocksDB のスキーマは同一
  # (新しい版で開くと戻せないので、移行前にバージョンを突き合わせてある)。
  # イメージが :latest で黙って上がっていく状態も、これで止まる。
  services.matrix-conduit = {
    enable = true;
    settings.global = {
      server_name = "gapul.net";
      # LAN に開ける必要がある。federation は Raspberry Pi の cloudflared が
      # matrix.gapul.net -> 192.168.116.98:6167 で渡してくる (トンネルは homelab-pi)。
      address = "0.0.0.0";
      # Conduit 本来のポート。8008 はコンテナが publish していた側の番号で、中の
      # Conduit は最初から 6167 だった。ブリッジの config も http://conduit:6167 を
      # 見ているので、素の番号に揃えて Cloudflare の ingress をそちらへ向けた。
      port = 6167;
      database_backend = "rocksdb";
      allow_registration = false;
      allow_federation = true;
      allow_check_for_updates = false;
      max_request_size = 20000000;
      trusted_servers = [ "matrix.org" ];
    };
  };

  # Conduit が podman のネットワークから出たので、ブリッジが名前で呼んでいた相手を
  # ホスト側で解決させる。Conduit に登録済みの appservice の URL は RocksDB の中にあり
  # admin room からしか変えられないので、名前は変えずに向き先だけ合わせる。
  networking.hosts."127.0.0.1" = [
    "mautrix-discord"
    "mautrix-telegram"
  ];

  # cloudflared (Pi) と podman ブリッジ側のコンテナから届く必要がある。閉じていると
  # DROP なので接続拒否ではなくタイムアウトになり、ブリッジ側は「homeserver に繋がらない」
  # としか言わない。コンテナが 8008 を publish していた頃と露出範囲は同じ。
  networking.firewall.allowedTCPPorts = [ 6167 ];

  # Containers
  virtualisation.oci-containers.containers."mautrix-discord" = {
    image = "dock.mau.dev/mautrix/discord:latest";
    environmentFiles = [ "/var/lib/secrets/matrix.env" ];
    volumes = [
      "/var/lib/homelab/matrix/bridges/discord:/data:rw"
    ];
    ports = [
      "29334:29334/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=mautrix-discord"
      "--network=matrix_default"
      # config.yaml の homeserver.address は http://conduit:6167 のまま。Conduit が
      # ホストへ出たので、その名前をホストの gateway に向ける。
      "--add-host=conduit:host-gateway"
    ];
  };
  systemd.services."podman-mautrix-discord" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-matrix_default.service"
    ];
    requires = [
      "podman-network-matrix_default.service"
    ];
    partOf = [
      "podman-compose-matrix-root.target"
    ];
    wantedBy = [
      "podman-compose-matrix-root.target"
    ];
  };
  virtualisation.oci-containers.containers."mautrix-telegram" = {
    image = "dock.mau.dev/mautrix/telegram:latest";
    environmentFiles = [ "/var/lib/secrets/matrix.env" ];
    volumes = [
      "/var/lib/homelab/matrix/bridges/telegram:/data:rw"
    ];
    # コンテナ同士なら network 越しで足りていたが、Conduit がホストに出たので
    # appservice の受け口を publish する。登録済みの URL は http://mautrix-telegram:29317。
    ports = [
      "29317:29317/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=mautrix-telegram"
      "--network=matrix_default"
      "--add-host=conduit:host-gateway"
    ];
  };
  systemd.services."podman-mautrix-telegram" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-matrix_default.service"
    ];
    requires = [
      "podman-network-matrix_default.service"
    ];
    partOf = [
      "podman-compose-matrix-root.target"
    ];
    wantedBy = [
      "podman-compose-matrix-root.target"
    ];
  };

  # signal / slack / meta / twitter はここにあったが落とした。移行で壊れたのではなく
  # 最初から繋がっていない (2026-08-11 に中身を確認):
  #   signal, slack : homeserver.address が既定の http://example.localhost:8008 のまま。DB なし。
  #   meta, twitter : address は合っているが domain が matrix.gapul.net。server_name は
  #                   gapul.net なのでこれでは通らない。DB は 512 バイトの空。
  # つまり4本とも再起動ループで空回りしていた。/var/lib/homelab/matrix/bridges 配下の
  # ディレクトリはそのまま残してあるので、使う気になったらここへ戻す。

  # Networks
  systemd.services."podman-network-matrix_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f matrix_default";
    };
    script = ''
      podman network inspect matrix_default || podman network create matrix_default
    '';
    partOf = [ "podman-compose-matrix-root.target" ];
    wantedBy = [ "podman-compose-matrix-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."podman-compose-matrix-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
