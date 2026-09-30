# Unified calendar feed (merges Google / iCloud / the home Radicale / any .ics into one feed).
# It used to be a Cloudflare Worker, but when personal events moved from Google Calendar to the
# home Radicale (radicale.nix), the policy changed to keep it self-contained inside homeserver.
#
# On 2026-09-26 the container from a private repo (ghcr.io/gapul/unified-calendar) was dropped
# and this was made self-contained within this repo. The container version never started because
# GHCR auth failed (image pull gave invalid username/password, stopped at start-limit-hit), and
# ical.gapul.net was returning 502. Putting credentials on homeserver just to pull a private
# image is not worth it. All it does is "fetch a few .ics files, cut them to a window and merge
# them into one", and it needs no resident process.
#
# The setup is a timer plus static serving. The script writes <token>.ics and Caddy serves that
# directory as-is. The feed URL itself is the secret, so an unguessable path is enough
# (this design is inherited from the original implementation; that is feeds[].tokenEnv).
#
# Secrets are not in the code; they are passed from under /var/lib/secrets/ (restored from
# homelab.yaml by sops-nix via secrets.nix). The calendar URLs themselves are secret, so the
# whole config lives there.
{
  config,
  pkgs,
  ...
}:
let
  port = 8113;
  dataDir = "/var/lib/homelab/unified-calendar";
  publicDir = "${dataDir}/public";

  python = pkgs.python3.withPackages (ps: [
    ps.icalendar
    ps.pyyaml
  ]);
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 unified-calendar unified-calendar -"
    # Only what Caddy reads is visible to others. Without the token, file names cannot be guessed.
    "d ${publicDir} 0755 unified-calendar unified-calendar -"
  ];

  users.users.unified-calendar = {
    isSystemUser = true;
    group = "unified-calendar";
  };
  users.groups.unified-calendar = { };

  systemd.services.unified-calendar = {
    description = "Rebuild the merged calendar feeds";
    serviceConfig = {
      Type = "oneshot";
      User = "unified-calendar";
      Group = "unified-calendar";
      EnvironmentFile = "/var/lib/secrets/unified-calendar.env";
      # Keep the previous output on failure. For subscribers, stale events beat an empty feed.
      SuccessExitStatus = [ 1 ];
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ dataDir ];
    };
    environment = {
      CONFIG_FILE = "/var/lib/secrets/unified-calendar.yaml";
      OUT_DIR = publicDir;
    };
    script = "${python}/bin/python3 ${../../configs/homelab/unified-calendar/build-feeds.py}";
  };

  systemd.timers.unified-calendar = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # The acceptable delay for new events is 15 minutes. Google's .ics only updates at about
      # the same granularity, so tightening this further brings in nothing more.
      OnBootSec = "3min";
      OnUnitActiveSec = "15min";
      Persistent = true;
    };
  };

  # cloudflared routes ical.gapul.net to this port. They are static files, so no upstream is
  # needed; Caddy serves the directory directly.
  services.caddy.virtualHosts.":${toString port}".extraConfig = ''
    root * ${publicDir}
    # "/" には何も無い (フィードは <トークン>.ics だけ) ので file_server は 404 を返し、
    # gatus の疎通確認 (homeserver.nix の sites 表、[STATUS] < 400) が常に赤になる。
    # ルートだけ 204 で応える。中身は出さないのでトークンは漏れない。
    @root path /
    respond @root 204
    # ディレクトリ一覧を出すとトークンが漏れる。file_server は browse を付けない。
    file_server
    header Content-Type "text/calendar; charset=utf-8"
    # 購読側は数分おきに取りに来る。生成が15分間隔なので、それに合わせる。
    header Cache-Control "max-age=300"
  '';

  # So Caddy can read the output. dataDir itself stays 0750; only public is let through.
  users.users.${config.services.caddy.user}.extraGroups = [ "unified-calendar" ];
}
