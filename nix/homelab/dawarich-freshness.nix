# 位置ログの鮮度を見る。6 時間おき。
#
# Dawarich 本体は dawarich.nix。こちらは「記録が続いているか」だけを見る。
#
# 分けてあるのは、これが本体の健康とは別の問いだから。2026-08-23 に位置ログが
# 36 時間止まっていたのが見つかったが、そのあいだ Dawarich は正常に動いていた。
# 止まっていたのは iPhone 側の Overland で、サーバから見て壊れているものは何も
# 無い。gatus は HTTP の応答しか見ないので、この形の停止は原理的に捕まらない。
#
# restic の monitor が最後のスナップショットの日付を見ているのと同じ考え方で、
# 「動いているか」ではなく「入ってきているか」を見る。位置ログは取り直しが
# 効かないので、気付くのが遅れた分だけ永久に空白になる。
{
  pkgs,
  ...
}:
{
  systemd.services.dawarich-freshness = {
    description = "位置ログに新しい点が来ているか";
    path = with pkgs; [
      podman
      curl
      coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/dawarich-freshness.sh} 24";
    };
  };

  systemd.timers.dawarich-freshness = {
    description = "位置ログの鮮度を 6 時間おきに見る";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # 閾値は 24 時間なので、6 時間おきに見れば「丸一日以上止まっている」ことに
      # 最大 30 時間で気付く。1 時間おきにしても早く気付けるわけではない。
      OnBootSec = "15min";
      OnUnitActiveSec = "6h";
      Persistent = true;
    };
  };
}
