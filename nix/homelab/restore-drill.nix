# バックアップから実際に復元してみる訓練。月に1回。
#
# backup.nix が取る側で、restic の check がリポジトリの整合を見る側。どちらも
# 「戻せるか」には答えない。2026-08 に見つかったのがまさにそこで、稼働中の
# postgres をファイルとしてコピーしていて、転送は毎日成功していたのに復元できる
# 保証が無かった。ダンプを取るように直したが、その直し自体は検証していない。
#
# スナップショットの中にダンプが入っていることは目で見れば分かる。それは
# 「ファイルがある」であって「復元できる」ではない。ここでやるのは後者で、
# 使い捨ての postgres を立てて本当に pg_restore する。
{
  pkgs,
  ...
}:
{
  systemd.services.restore-drill = {
    description = "バックアップから実際に復元してみる";
    path = with pkgs; [
      restic
      rclone
      podman
      sqlite
      curl
      coreutils
      hostname
    ];
    environment = {
      RESTIC_REPOSITORY = (import ../lib/restic-common.nix { home = "/root"; }).repository;
      RESTIC_PASSWORD_FILE = "/var/lib/secrets/restic.password";
      RCLONE_CONFIG = "/var/lib/secrets/rclone.conf";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/restore-drill.sh}";
      # 使い捨ての postgres を起動して数百 MB を展開する。バックアップ本体と
      # ぶつからないよう、時刻は 03:00 から離してある。
      TimeoutStartSec = "60min";
    };
  };

  systemd.timers.restore-drill = {
    description = "復元訓練を月に1回";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "monthly";
      # 月初に一斉に走らせる必要は無い。バックアップ (03:00) と重ならない時刻。
      RandomizedDelaySec = "6h";
      Persistent = true;
    };
  };
}
