# 統合カレンダー配信 (Google/iCloud/自宅Radicale/任意の .ics を1本のフィードにまとめる)。
# 元は Cloudflare Worker だったが、個人の予定を Google Calendar から自宅 Radicale へ
# 移した (radicale.nix) のに合わせて homeserver 内部で完結させる方針に変えた。
#
# 2026-09-26 に private リポジトリのコンテナ (ghcr.io/gapul/unified-calendar) をやめ、
# この repo の中で完結させた。コンテナ版は GHCR の認証が通らず一度も起動しておらず
# (image pull で invalid username/password、start-limit-hit で停止)、ical.gapul.net は
# 502 を返していた。private イメージを引くためだけに資格情報を homeserver に置くのは
# 割に合わない。やることは「.ics をいくつか取ってきて窓で切って1本にまとめる」だけで、
# 常駐プロセスも要らない。
#
# 構成は timer + 静的配信。スクリプトが <トークン>.ics を書き、Caddy がそのディレクトリを
# そのまま出す。フィードの URL 自体が秘密なので、パスが推測できなければそれで足りる
# (この設計は元の実装から引き継いでいる。feeds[].tokenEnv がそれ)。
#
# 秘密はコードに置かず /var/lib/secrets/ 配下から渡す (secrets.nix 経由で sops-nix が
# homelab.yaml から復元する)。カレンダーの URL 自体が秘密なので設定ごとそちらに置く。
{
  config,
  pkgs,
  ...
}:
let
  port = 8113;
  dataDir = "/var/lib/homelab/unified-calendar";
  publicDir = "${dataDir}/public";

  python = pkgs.python3.withPackages (ps: [
    ps.icalendar
    ps.pyyaml
  ]);
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 unified-calendar unified-calendar -"
    # Caddy が読む先だけ他から見える。トークンを知らないとファイル名が当たらない。
    "d ${publicDir} 0755 unified-calendar unified-calendar -"
  ];

  users.users.unified-calendar = {
    isSystemUser = true;
    group = "unified-calendar";
  };
  users.groups.unified-calendar = { };

  systemd.services.unified-calendar = {
    description = "Rebuild the merged calendar feeds";
    serviceConfig = {
      Type = "oneshot";
      User = "unified-calendar";
      Group = "unified-calendar";
      EnvironmentFile = "/var/lib/secrets/unified-calendar.env";
      # 失敗しても前回の出力を残す。購読側から見れば古い予定のほうが空より良い。
      SuccessExitStatus = [ 1 ];
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ dataDir ];
    };
    environment = {
      CONFIG_FILE = "/var/lib/secrets/unified-calendar.yaml";
      OUT_DIR = publicDir;
    };
    script = "${python}/bin/python3 ${../../configs/homelab/unified-calendar/build-feeds.py}";
  };

  systemd.timers.unified-calendar = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # 予定の追加が反映されるまでの許容が15分。Google 側の .ics も同程度の粒度でしか
      # 更新されないので、これ以上詰めても取り込めるものが増えない。
      OnBootSec = "3min";
      OnUnitActiveSec = "15min";
      Persistent = true;
    };
  };

  # cloudflared が ical.gapul.net をこのポートに流す。静的ファイルなので upstream は
  # 要らず、Caddy が直接ディレクトリを出す。
  services.caddy.virtualHosts.":${toString port}".extraConfig = ''
    root * ${publicDir}
    # ディレクトリ一覧を出すとトークンが漏れる。file_server は browse を付けない。
    file_server
    header Content-Type "text/calendar; charset=utf-8"
    # 購読側は数分おきに取りに来る。生成が15分間隔なので、それに合わせる。
    header Cache-Control "max-age=300"
  '';

  # 生成結果を Caddy が読めるように。dataDir 自体は 0750 のままで、public だけ通す。
  users.users.${config.services.caddy.user}.extraGroups = [ "unified-calendar" ];
}
