# iPhone のヘルスケアを自宅に貯める受け口 (health.gapul.net)。
#
# 送る側は PulsHealth (iOS、Apache-2.0、App Store 配布)。HealthKit を読み取り専用で読み、
# 過去分を丸ごと送ったあとは差分を gzip NDJSON で POST してくる。送り先は設定した
# サーバーだけで、開発者にも第三者にも行かないことはソースで確認した (2026-09-15)。
#
# 受ける側は公式の重い構成 (TimescaleDB + Go + Grafana) ではなく、同梱の Python + SQLite
# の例を configs/homelab/puls-receiver に持ってきたもの。展開後サイズの上限だけ足してある。
# 標準ライブラリだけで動き、DB は 1 ファイル。
#
# 認証はアプリが持つ bearer トークン (/var/lib/secrets/puls.env の PULS_TOKEN) なので、
# vhost に Authelia は挟まない。アプリの URL 検証は tailnet の 100.x に平文 http を許さないため、
# Caddy の HTTPS を通す。
{ pkgs, ... }:

{
  systemd.services.puls-receiver = {
    description = "PulsHealth receiver (Apple Health → SQLite)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      PULS_DB = "/var/lib/puls/health.db";
      PULS_BIND = "127.0.0.1";
      PULS_PORT = "8105";
    };
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${../../configs/homelab/puls-receiver/receiver.py}";
      EnvironmentFile = "/var/lib/secrets/puls.env";
      DynamicUser = true;
      StateDirectory = "puls";
      StateDirectoryMode = "0700";
      Restart = "always";
      RestartSec = 10;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      MemoryMax = "1G";
    };
  };
}
