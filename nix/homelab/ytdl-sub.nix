# YouTube archiving without a web-only control plane.  Subscriptions live in
# git as YAML and both validation and downloads use the same ytdl-sub CLI.
{
  pkgs,
  ...
}:
let
  configFile = ../../configs/homelab/ytdl-sub-config.yaml;
  subscriptionsFile = ../../configs/homelab/ytdl-sub-subscriptions.yaml;
in
{
  environment.systemPackages = [ pkgs.ytdl-sub ];

  systemd.tmpfiles.rules = [
    "d /var/lib/ytdl-sub 0755 root root -"
    "d /var/lib/ytdl-sub/work 0755 root root -"
    "d /var/log/ytdl-sub 0755 root root -"
    "d /srv/youtube 0755 root root -"
  ];

  systemd.services.ytdl-sub = {
    description = "Download declarative video subscriptions";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [
      ffmpeg
      yt-dlp
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ytdl-sub}/bin/ytdl-sub --config ${configFile} sub ${subscriptionsFile}";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };

  systemd.timers.ytdl-sub = {
    description = "Check video subscriptions every six hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00/6:17:00";
      RandomizedDelaySec = "20m";
      Persistent = true;
    };
  };

  services.logrotate.settings.ytdl-sub = {
    files = "/var/log/ytdl-sub/*.log";
    frequency = "weekly";
    rotate = 4;
    compress = true;
    missingok = true;
  };
}
