# GitHub の自分のリポジトリを全部 Forgejo (git.gapul.net) に pull mirror として持つ。
#
# GitHub にしか無いコードを、アカウント停止や誤削除から守るため。ミラーの定期取得は
# Forgejo 自身が mirror_interval (8h) で回すので、ここは「新しく増えたリポジトリに
# ミラーを作る」だけを 1 日 1 回やる。GitHub で消えたリポジトリのミラーは残す。
#
# /var/lib/secrets/github-mirror.env:
#   GITHUB_TOKEN  fine-grained PAT (gapul の全リポジトリ、Contents と Metadata の read)。
#                 各ミラーの取得にもこの値が保存されるので、作り直したら Forgejo 側も要更新
#   FORGEJO_TOKEN forgejo admin user generate-access-token で作ったもの
{ pkgs, ... }:

{
  systemd.services.github-mirror = {
    description = "Create Forgejo pull mirrors for new GitHub repositories";
    after = [
      "network-online.target"
      "podman-forgejo.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${../../configs/homelab/github-mirror/github-mirror.py}";
      EnvironmentFile = "/var/lib/secrets/github-mirror.env";
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  systemd.timers.github-mirror = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:10:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };
}
