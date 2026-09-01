# 動いている構成に既知の脆弱性が無いかを見る。
#
# ローリングに切り替えた (flake.nix の nixpkgs-nixos) ので「見つかったら直す」が
# 方針になったが、**見つける経路が無かった**。上流が直しても、こちらがそれを知る
# 手段が人の耳しかない。ここはその穴を埋めるためだけにある。
#
# 直すのは別系統。update-flake-lock が毎時走り、CI を通ってから self-deploy が
# 取りに行くので、上流に修正が入っていれば最悪 2 時間で当たる。ここがやるのは
# 「まだ当たっていないものを知らせる」ことだけ。
{ pkgs, ... }:
{
  systemd.services.vulnix-scan = {
    description = "稼働中の構成に既知の脆弱性が無いか見る";
    path = with pkgs; [
      vulnix
      curl
      gnugrep
      coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/vulnix-scan.sh}";
      StateDirectory = "vulnix";
      # NVD のデータを取りに行くので少し時間がかかる。
      TimeoutStartSec = "30min";
    };
  };

  systemd.timers.vulnix-scan = {
    description = "脆弱性の照合を 1 日 1 回走らせる";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # 毎時にしても NVD 側がその速さで更新されないので意味が無い。
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
