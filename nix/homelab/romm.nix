# RomM — the ROM library. Same idea as Jellyfin: browse what's on the shelf from the
# browser and play it right there (EmulatorJS runs in the browser).
#
# ROMs get their own service because they differ in nature from PC games. A ROM is one file
# per title and only becomes a shelf entry once metadata is pulled from outside (IGDB). A PC
# game is a bundle of installers, and all it needs is storage and a catalog. Using the same
# tool for both leaves both half-done. The PC side is gameyfin.nix.
#
# The actual files are in /srv/games/roms, on the large disk and excluded from restic.
# Same call as the rest of /srv: don't spend backup space on things that can be dumped again.
{
  pkgs,
  lib,
  ...
}:

let
  privatePort = 18091;
in
{
  virtualisation.oci-containers.containers."romm-db" = {
    image = "docker.io/library/mariadb:11";
    environment = {
      "MARIADB_DATABASE" = "romm";
      "MARIADB_USER" = "romm";
    };
    # MARIADB_ROOT_PASSWORD and MARIADB_PASSWORD come from romm.env.
    environmentFiles = [ "/var/lib/secrets/romm.env" ];
    volumes = [
      "/var/lib/homelab/romm/db:/var/lib/mysql:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=romm-db"
      "--network=romm_default"
      "--health-cmd=healthcheck.sh --connect --innodb_initialized"
      # No periodic runs (disable). --health-cmd itself remains, so
      # `podman healthcheck run romm-db`, used by backup.nix's wait_healthy, still works.
      #
      # While it ran periodically, the daily flake auto-upgrade (nixos-upgrade.service)
      # caused an incident every time it restarted this container. Right after the restart,
      # while MariaDB was still starting up, the first health check ran immediately and failed;
      # switch-to-configuration treated the failure of that transient systemd unit as a fatal
      # error, so even though the switch itself had completed, nixos-upgrade.service stayed
      # failed and got reported to ntfy (2026-09-21). Extending --health-start-period didn't
      # help because it doesn't change when the first run happens.
      "--health-interval=disable"
    ];
  };
  systemd.services."podman-romm-db" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";

    # Delete tc.log before starting.
    #
    # MariaDB keeps its transaction coordinator log here, but if the container is killed it is
    # left in a half-written state. The next start goes "Bad magic header in tc log" → "Crash
    # recovery failed" → Aborting, and it never comes up again. Hit twice, on 2026-08-28 and
    # 2026-09-01. The first went unnoticed for 2 days (it keeps restarting, so podman ps shows
    # it as Up).
    #
    # Deleting it is safe because this file is for two-phase commit coordination and is only
    # used when there are multiple transactional engines or a binlog. Here it's InnoDB alone
    # with no binlog, so there is nothing to coordinate with. InnoDB's own recovery lives in
    # ib_logfile, which is intact (indeed, even when it broke, the log sequence number and
    # buffer pool were readable).
    #
    # MariaDB itself says "delete tc log and start server" in this situation.
    serviceConfig.ExecStartPre = [
      "-${pkgs.coreutils}/bin/rm -f /var/lib/homelab/romm/db/tc.log"
    ];

    # Reduce forced kills in the first place. The default 10 seconds sometimes isn't enough
    # for InnoDB to finish flushing, and if it doesn't finish it gets SIGKILL, producing the state above.
    serviceConfig.TimeoutStopSec = 120;
    after = [ "podman-network-romm_default.service" ];
    requires = [ "podman-network-romm_default.service" ];
    partOf = [ "podman-compose-romm-root.target" ];
    wantedBy = [ "podman-compose-romm-root.target" ];
  };

  virtualisation.oci-containers.containers."romm" = {
    image = "docker.io/rommapp/romm:latest";
    environment = {
      "DB_HOST" = "romm-db";
      "DB_NAME" = "romm";
      "DB_USER" = "romm";
      # Hasheous is keyless hash matching (No-Intro/Redump). It identifies ROMs before IGDB,
      # so they land on the shelf correctly even with sloppy file names.
      "HASHEOUS_API_ENABLED" = "true";
    };
    # DB_PASSWD / ROMM_AUTH_SECRET_KEY / IGDB_CLIENT_ID / IGDB_CLIENT_SECRET.
    # Without the two IGDB ones, metadata can't be fetched and the shelf is just a list of file names.
    environmentFiles = [ "/var/lib/secrets/romm.env" ];
    volumes = [
      "/var/lib/homelab/romm/resources:/romm/resources:rw" # fetched cover images
      "/var/lib/homelab/romm/redis:/redis-data:rw"
      "/srv/games/roms:/romm/library:rw"
      "/srv/games/roms-assets:/romm/assets:rw" # save data and states
    ];
    ports = [ "127.0.0.1:${toString privatePort}:8080/tcp" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=romm"
      "--network=romm_default"
    ];
    dependsOn = [ "romm-db" ];
  };
  systemd.services."podman-romm" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-romm_default.service" ];
    requires = [ "podman-network-romm_default.service" ];
    partOf = [ "podman-compose-romm-root.target" ];
    wantedBy = [ "podman-compose-romm-root.target" ];
  };

  systemd.services."podman-network-romm_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "${pkgs.podman}/bin/podman network rm -f romm_default";
    };
    script = ''
      podman network inspect romm_default || podman network create romm_default
    '';
    partOf = [ "podman-compose-romm-root.target" ];
    wantedBy = [ "podman-compose-romm-root.target" ];
  };

  systemd.targets."podman-compose-romm-root" = {
    unitConfig = {
      Description = "romm (ROM ライブラリ)";
      StopWhenUnneeded = true;
    };
    wantedBy = [ ];
  };

  # RomM looks at per-platform subdirectories (roms/gb, roms/snes, ...).
  # Unless they exist, even empty, the first scan ends with "no library".
  systemd.tmpfiles.rules = [
    # podman doesn't create bind mount sources (unlike docker). Starting without them returns
    # 125 with `statfs ...: no such file or directory`, restarts repeatedly, and stops at
    # start-limit-hit.
    "d /var/lib/homelab/romm 0700 root root -"
    # MariaDB drops to uid/gid 999.  The mount root must remain traversable by
    # that user; otherwise existing open tables appear to work while metadata
    # operations such as mariadb-dump fail with EACCES.
    "d /var/lib/homelab/romm/db 0700 999 999 -"
    "d /var/lib/homelab/romm/resources 0700 root root -"
    "d /var/lib/homelab/romm/redis 0700 root root -"
    "d /srv/games 0755 root root -"
    "d /srv/games/roms 0755 root root -"
    "d /srv/games/roms-assets 0755 root root -"
  ];
}
