# Personal class schedule from UTAS, mirrored into the home Radicale as the "授業" calendar
# (gapul/cal-classes). unified-calendar.nix is the feed shown to other people; this one is only
# for me, so it goes through the same CalDAV account every client already has.
#
# UTAS rebuilds the .ics around 01:00 JST, so one run a little after that is enough.
# The UTAS URL and the Radicale credentials are secret: /var/lib/secrets/utas-classes.env
# (UTAS_ICS_URL, RADICALE_USER, RADICALE_PASSWORD), restored from homelab.yaml by secrets.nix.
{ pkgs, ... }:
{
  systemd.services.utas-classes = {
    description = "Mirror the UTAS class calendar into Radicale";
    after = [
      "network-online.target"
      "podman-radicale.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "utas-classes";
      EnvironmentFile = "/var/lib/secrets/utas-classes.env";
      ProtectHome = true;
      NoNewPrivileges = true;
    };
    environment.RADICALE_URL = "http://127.0.0.1:5232/gapul/cal-classes/";
    script = "${pkgs.python3}/bin/python3 ${../../configs/homelab/utas-classes/sync.py}";
  };

  systemd.timers.utas-classes = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 01:30:00";
      OnBootSec = "5min";
      Persistent = true;
    };
  };
}
