# Checks location log freshness, every 6 hours.
#
# Dawarich itself is dawarich.nix. This only checks "is recording still happening".
#
# It is separate because this is a different question from the service's health. On 2026-08-23 the
# location log was found to have stopped for 36 hours, while Dawarich was running normally the whole
# time. What had stopped was Overland on the iPhone, and nothing looked broken from the server.
# gatus only looks at HTTP responses, so this kind of stall can't be caught in principle.
#
# Same idea as the restic monitor checking the date of the last snapshot: check
# "is data coming in", not "is it running". Location logs can't be re-collected,
# so every bit of delay in noticing becomes a permanent gap.
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
      # The threshold is 24 hours, so checking every 6 hours notices "stopped for over a full day"
      # within 30 hours at most. Checking hourly wouldn't notice any sooner.
      OnBootSec = "15min";
      OnUnitActiveSec = "6h";
      Persistent = true;
    };
  };
}
