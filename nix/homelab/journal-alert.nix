# Periodically scan journald and send signs of breakage to ntfy.
#
# Log aggregation itself is already in place. All 30 containers use log-driver=journald, so a
# single `journalctl` searches across everything. When 6 bugs were dug out on 2026-08-16, all
# the needed information was there. What was missing was that "nobody goes to look", and
# gatus stayed green as long as HTTP returned 200.
#
# So Loki is not installed. Reconsider if cross-cutting queries into the past become needed.
# As of 2026-09-23, 13 days took 2.5GB. To keep things investigable without unbounded growth,
# the limit is 2GB of space or at most 90 days, whichever is reached first.
{ pkgs, ... }:
{
  services.journald.settings.Journal = {
    SystemMaxUse = "2G";
    MaxRetentionSec = "90day";
  };

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
      # Where "the content and time last alerted for this signal" is stored. Used for throttling
      # so a single unfixed issue doesn't keep alerting every 15 minutes (28 messages in 7 hours on 2026-09-13).
      StateDirectory = "journal-alert";
    };
  };

  systemd.timers.journal-alert = {
    description = "journal-alert を 15 分おきに走らせる";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Same interval as the search window. Offsetting it either misses entries or alerts twice.
      OnBootSec = "10min";
      OnUnitActiveSec = "15min";
      Persistent = true;
    };
  };
}
