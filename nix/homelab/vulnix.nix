# Check the running configuration for known vulnerabilities.
#
# After switching to rolling (nixpkgs-nixos in flake.nix), the policy became "fix it when
# found", but **there was no way to find anything**. Even when upstream fixed something, the
# only way to learn of it was word of mouth. This exists solely to fill that gap.
#
# Fixing is a separate pipeline. update-flake-lock runs hourly and self-deploy fetches after
# CI passes, so once upstream has a fix it lands within 2 hours at worst. All this does is
# "report what hasn't landed yet".
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
      # It fetches NVD data, so it takes a while.
      TimeoutStartSec = "30min";
    };
  };

  systemd.timers.vulnix-scan = {
    description = "脆弱性の照合を 1 日 1 回走らせる";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Hourly would be pointless since NVD doesn't update that fast.
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
