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
  # Pin the owner of the sync targets to syncthing. Right after the migration /srv/syncthing
  # was still uid 101000 (the subuid from the old CT101 rootless-container days), and native
  # syncthing (uid 237) couldn't write to its own folders. It went unnoticed until 2026-08-16,
  # showing up as SyncHub being empty except for .stfolder even though the Mac was connected.
  systemd.tmpfiles.rules = [
    "d /srv/syncthing 0755 syncthing syncthing -"
    "Z /srv/syncthing - syncthing syncthing -"
    # Paperless inbox (folder below). Syncthing (uid 237) writes here and the paperless container
    # (uid 1000, no userns) deletes each file once consumed, so both need write on the directory.
    # Files arrive 0644, readable by paperless; the directory is the only thing opened up.
    "d /var/lib/homelab/paperless/consume 0777 1000 1000 -"
  ];

  services.syncthing = {
    enable = true;
    # The old container ran GUI on 8384 and sync on 22000, fronted at
    # sync.gapul.net; keep the numbers so the caddy vhost and the Mac's configured
    # address both still fit.
    guiAddress = "127.0.0.1:8384";
    openDefaultPorts = true;
    settings = {
      devices."macbook-mini".id = "3YUCLFD-KVCQOP4-KF4CPIA-MA5EDJH-QO6NQ7V-CHH3LVZ-GQTNFQZ-A4LEWQ2";
      # The iPhone runs Synctrain (an iOS Syncthing client). The ID was read from
      # "This device's identifier" on the app's Start screen. It's a public key, so it's safe to commit.
      devices."iphone" = {
        id = "R3V5V7Y-ZRBHIHY-F35M3PX-4H3I73G-4UA7UHT-CH523JH-O37RSW3-PNLJPAX";
        # Keep it reachable via relays even on mobile data. Inside the tailnet it connects directly.
        introducer = false;
      };
      # Xiaomi Pad 5 running Syncthing-Fork (com.github.catfriend1.syncthingfork, managed
      # by Obtainium, see configs/android/obtainium.json). ID from the app's "Show device ID".
      devices."xiaomi-pad5".id = "M6ORNMD-BGMQFH5-7EXMWNZ-2MTSGYD-62HWC6H-UCCB3R3-QUSGIV5-T7PDVAH";
      # Where personal records are collected. Each device gets its own <hostname>/ and only
      # writes to its own directory. No file is ever written by more than one device, so
      # conflicts can't happen structurally (see home/personal-history.nix).
      # Not distributed to the iPhone. Only the main Mac and macmini read it, and it's large.
      folders."personal-history" = {
        label = "Personal History";
        path = "/srv/syncthing/personal-history";
        devices = [ "macbook-mini" ];
        type = "sendreceive";
      };
      # Drop a PDF on the Mac or save a scan on the iPhone and Paperless consumes it. This side is
      # Paperless' consume directory itself: consumed files are deleted, and sendreceive carries
      # the deletion back, so an emptied inbox is the confirmation. Syncthing's .stfolder and
      # temp files are in Paperless' default ignore list.
      folders."paperless-inbox" = {
        label = "Paperless Inbox";
        path = "/var/lib/homelab/paperless/consume";
        devices = [
          "macbook-mini"
          "iphone"
        ];
        type = "sendreceive";
      };
      # The Obsidian vault. Syncing the contents is LiveSync's job (obsidian-couchdb.nix);
      # this is a one-way copy only for keeping history: the main Mac sends, this side only
      # receives (receiveonly). There's a single writer, so it doesn't fight with LiveSync.
      # Commits come from the hourly timer in vault-git.nix.
      folders."obsidian-vault" = {
        label = "Obsidian Vault";
        path = "/srv/syncthing/obsidian-vault";
        devices = [ "macbook-mini" ];
        type = "receiveonly";
        # Files in the main Mac's vault are 0600; copied as is, the vault-git user (which is
        # in the syncthing group) couldn't read them and the first commit failed with
        # "open(.gitignore): Permission denied". Not carrying permissions makes them 0644 via
        # syncthing's own umask. The sending side has the same setting.
        ignorePerms = true;
      };
      # The tablet's whole internal storage (/storage/emulated/0), so its files can be read and
      # edited from here. Android/, trash and device logs are excluded by /sdcard/.stignore (configs/android/stignore) on
      # the tablet. Deletions on the tablet propagate, so removed or overwritten files are kept
      # in .stversions for 30 days. Not in the restic set (backup.nix): this is the second copy
      # of the tablet, not the only one.
      folders."android-pad5" = {
        label = "Xiaomi Pad 5";
        path = "/srv/syncthing/android-pad5";
        devices = [ "xiaomi-pad5" ];
        type = "sendreceive";
        versioning = {
          type = "trashcan";
          params.cleanoutDays = "30";
        };
      };
      folders."synchub" = {
        label = "SyncHub";
        # Was /mnt/jellyfin-media/syncthing/SyncHub on the old host, mounted into
        # the container as /data/SyncHub.
        path = "/srv/syncthing/SyncHub";
        devices = [
          "macbook-mini"
          "iphone"
        ];
        type = "sendreceive";
      };
    };
  };
}
