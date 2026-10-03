# Checks location log freshness, every hour.
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
      # 3 hours: since Overland took over (2026-09-24) the phone sends points around the clock,
      # at home and asleep included, so every gap over 3 hours has been Overland stopping (15, 30
      # and 35 hours in the week to 2026-10-03, each noticed only after the fact). At 24 hours the
      # alert came a day late; at 3 the phone can be woken the same morning or evening.
      ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/dawarich-freshness.sh} 3";
      StateDirectory = "dawarich-freshness"; # remembers which stall was already notified
    };
  };

  systemd.timers.dawarich-freshness = {
    description = "位置ログの鮮度を 1 時間おきに見る";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Hourly against a 3-hour threshold: a stall is reported within 4 hours. One notification
      # per stall (the script keeps the last point it reported), so hourly doesn't mean noisy.
      OnBootSec = "15min";
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };
}
