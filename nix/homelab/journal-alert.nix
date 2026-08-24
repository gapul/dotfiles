# journald の中身を定期的に見て、壊れの合図を ntfy に流す。
#
# ログ集約そのものは既にできている。30 コンテナすべてが log-driver=journald
# なので、`journalctl` 一本で横断検索が効く。2026-08-16 に 6 件の不具合を
# 掘り出したときも、必要な情報は全部そこにあった。足りなかったのは
# 「誰も見に行かない」ことの方で、gatus は HTTP が 200 なら緑のままだった。
#
# なので Loki は入れていない。過去に遡って横断クエリしたくなったら考える。
# いまは 5 日分で 1GB なので、保持を伸ばすだけなら journald の設定で済む。
{ pkgs, ... }:
{
  systemd.services.journal-alert = {
    description = "journald の壊れの合図を ntfy に流す";
    path = with pkgs; [
      curl
      gnugrep
      systemd
      coreutils
      gawk
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/journal-alert.sh} -15min";
    };
  };

  systemd.timers.journal-alert = {
    description = "journal-alert を 15 分おきに走らせる";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # 検索窓と同じ間隔にする。ずらすと取りこぼすか二重に鳴る。
      OnBootSec = "10min";
      OnUnitActiveSec = "15min";
      Persistent = true;
    };
  };
}
