_:
let
  # Same repository and the same retention as the Mac and the laptop. That file
  # is the single definition point on purpose: three hosts writing to one restic
  # repository with different forget policies is how snapshots get thinned out
  # from under each other.
  resticCommon = import ../lib/restic-common.nix { home = "/root"; };
in
{
  # Replaces backrest, the web UI for restic that ran as a container. The schedule
  # and the retention are the parts worth having in git; a UI to look at them is
  # not, and gatus already answers "did it run".
  services.restic.backups.homeserver = {
    inherit (resticCommon) repository;
    # Placed by hand at install time, like the other secrets here, until this host
    # has an age key for sops-nix.
    passwordFile = "/var/lib/secrets/restic.password";
    rcloneConfigFile = "/var/lib/secrets/rclone.conf";

    # /var/lib is where every service on this host keeps its state: the container
    # bind mounts under /var/lib/homelab, the named podman volumes, adguard,
    # syncthing's identity, gatus, the acme certs, samba's password db.
    paths = [ "/var/lib" ];
    exclude = [
      # Container images are re-pullable and would dominate the repository. The
      # volumes directory underneath is deliberately not excluded — that is data.
      "/var/lib/containers/storage/overlay"
      "/var/lib/containers/storage/overlay-images"
      "/var/lib/containers/storage/overlay-layers"
      "/var/lib/containers/cache"
      # Runtime scratch, regenerated on boot.
      "/var/lib/systemd/coredump"
    ];
    # /srv is not backed up. It holds media, the attic cache and archivebox's
    # dumps: large, and either re-obtainable or already content-addressed. The
    # exception is /srv/syncthing, which is a copy of what the Mac holds and is
    # backed up from there. Change this if that stops being true.

    pruneOpts = resticCommon.retentionArgs;
    extraBackupArgs = [ "--tag homeserver" ];
    timerConfig = {
      OnCalendar = "03:00";
      # The Mac writes to the same repository; restic locks, so a fixed hour on
      # both sides just means one of them waits.
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };

  # Known failure mode worth remembering: the rclone Google Drive token expires
  # after roughly a week of disuse and both hosts then fail silently. Until this
  # unit can notify (ntfy's token is sops-managed and waits for the host's age
  # key), check it with `systemctl status restic-backups-homeserver`.
}
