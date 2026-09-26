# 持ち物の台帳 (Homebox)。何を持っていて、どこにあって、いつ・いくらで買って保証がいつまでか。
#
# 主な使い手は人ではなく LLM で、REST API を叩いて登録・検索する。v0.26 から API キー
# (hb_ で始まる、発行したユーザーの権限を継ぐ) が使えるので、パスワードをスクリプトに
# 持たせずに済む。nixpkgs の homebox は 0.25 で API キーが無いため、モジュールではなく
# 公式イメージを使う。0.26 で items/locations の API は /v1/entities に統合された。
#
# 領収書や保証書の原本は Paperless にあり、ここには Paperless の URL を持たせるだけ。
# Go の単一バイナリと SQLite で、アイドル時のメモリは 50MB 未満。
{
  lib,
  ...
}:

{
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/homebox 0700 root root -"
  ];

  virtualisation.oci-containers.containers."homebox" = {
    image = "ghcr.io/sysadminsmedia/homebox:latest";
    # HBOX_AUTH_API_KEY_PEPPER (32 文字以上の乱数)。0.26 からこれが無いと起動しない。
    # 変えると発行済みの API キーが全部無効になる。
    environmentFiles = [ "/var/lib/secrets/homebox.env" ];
    environment = {
      # アカウントは 2026-09-26 に作成済みなので閉じた。tailnet の内側だけとはいえ、
      # 登録できる状態を残す理由が無い。増やすときだけ一時的に true にする。
      "HBOX_OPTIONS_ALLOW_REGISTRATION" = "false";
      "HBOX_LOG_FORMAT" = "text";
      "HBOX_WEB_MAX_UPLOAD_SIZE" = "20";
    };
    volumes = [
      "/var/lib/homelab/homebox:/data:rw"
    ];
    ports = [
      "127.0.0.1:8104:7745/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-homebox" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
