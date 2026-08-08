{
  # Syncthing, the one service whose whole configuration used to live in a web UI.
  # Devices and folders are declared here; the module reconciles them on start, so
  # pairing a new machine is a commit rather than a session of clicking.
  #
  # Device IDs are public keys, safe to commit. What must NOT be recreated is this
  # node's own identity in /var/lib/syncthing (cert.pem, key.pem): losing it gives
  # the host a new device ID and the Mac would have to re-accept it and rescan the
  # whole folder. That directory is part of the data to migrate, not something to
  # regenerate.
  services.syncthing = {
    enable = true;
    # The old container ran GUI on 8384 and sync on 22000, fronted at
    # sync.gapul.net; keep the numbers so the caddy vhost and the Mac's configured
    # address both still fit.
    guiAddress = "127.0.0.1:8384";
    openDefaultPorts = true;
    settings = {
      devices."macbook-mini".id = "3YUCLFD-KVCQOP4-KF4CPIA-MA5EDJH-QO6NQ7V-CHH3LVZ-GQTNFQZ-A4LEWQ2";
      folders."synchub" = {
        label = "SyncHub";
        # Was /mnt/jellyfin-media/syncthing/SyncHub on the old host, mounted into
        # the container as /data/SyncHub.
        path = "/srv/syncthing/SyncHub";
        devices = [ "macbook-mini" ];
        type = "sendreceive";
      };
    };
  };
}
