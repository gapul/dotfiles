# 家計簿。beancount の台帳 (ただのテキスト) を fava で読む。
#
# Firefly III ではなくこちらにした理由。複式簿記なのはどちらも同じだが、Firefly III
# は PHP と postgres が要り、記録が DB の中に沈む。ここでやりたいのは Zaim が集めて
# きたものを取り込んで眺めることで、その形なら台帳はテキストで足りる。テキストなら
# git に入って差分が読めるし、壊れても手で直せる。DB のダンプを復元する話にならない。
#
# 失うのは、スマホからその場で入力する手軽さ。入力源が Zaim である限り問題にならない。
#
# 認証は無い。fava はリバースプロキシの後ろに置く前提の道具で、ログインを持たない。
# ここでの境界は tailnet で、caddy の vhost は tailnet アドレスにしか生えていない。
# 家計の記録をそこに置いてよいかは、tailnet 上の端末を全部自分のものとみなすか
# どうかの判断になる。外に出すなら caddy 側で認証を足すこと。
{
  pkgs,
  ...
}:
let
  ledgerDir = "/var/lib/homelab/fava";
  mainLedger = "${ledgerDir}/main.beancount";
in
{
  systemd.tmpfiles.rules = [
    "d ${ledgerDir} 0700 root root -"
    # 台帳が無いと fava は起動しない。空の状態で立ち上がるように最小の 1 行を置く。
    # 既にあれば触らない (f は「無ければ作る」)。
    "f ${mainLedger} 0600 root root - option \"operating_currency\" \"JPY\"\n"
  ];

  systemd.services.fava = {
    description = "fava (beancount の閲覧 UI)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.fava}/bin/fava --host 127.0.0.1 --port 8093 ${mainLedger}";
      Restart = "always";
      RestartSec = 10;
      # 台帳以外に触る必要がない。
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ ledgerDir ];
      NoNewPrivileges = true;
    };
  };

  # 台帳を編集するのに beancount 側の道具も要る (bean-check で検算する)。
  environment.systemPackages = [ pkgs.beancount ];
}
