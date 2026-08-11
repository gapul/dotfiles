{
  # Whole-disk layout for the home server. Unlike nixos-laptop (which shares its NVMe
  # with Windows and therefore lets disko only format one LUKS partition), this box is
  # dedicated, so disko owns the entire disk and generates the fileSystems config too.
  # That is what makes a hand-placed hardware-configuration.nix unnecessary here.
  #
  # Format and mount at install time with:
  #   sudo disko --mode destroy,format,mount --flake <repo>/nix#homeserver
  #
  # ZFS rather than ext4 for one reason: it is the replacement for the per-guest
  # vzdump snapshots that Proxmox provided. A single-disk pool already gives
  # snapshots and rollback; attaching a second NVMe later converts it to a mirror
  # (`zpool attach rpool <old> <new>`) without reinstalling.
  disko.devices = {
    disk.main = {
      type = "disk";
      # The machine has exactly one NVMe, so the short name is unambiguous. Kept
      # instead of /dev/disk/by-id/... to avoid committing the drive serial to a
      # public repo; revisit if a second disk is added.
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "rpool";
            };
          };
        };
      };
    };

    zpool.rpool = {
      type = "zpool";
      options.ashift = "12";
      rootFsOptions = {
        # lz4, not zstd. Thirty-odd services write to this pool continuously and
        # zstd costs several times the CPU per write for space this machine does
        # not need — 18GB of 472GB is in use. Changed on the running pool too;
        # compression is per-block, so what is already written stays zstd.
        compression = "lz4";
        atime = "off";
        # Needed by systemd and by several services that store extended attributes.
        xattr = "sa";
        acltype = "posixacl";
        mountpoint = "none";
        "com.sun:auto-snapshot" = "true";
      };
      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
        };
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
          # The store is reproducible from the flake, so snapshotting it only
          # burns space.
          options."com.sun:auto-snapshot" = "false";
        };
        # All service state lives here, which is the granularity that matters:
        # rolling back a bad container upgrade should not roll back the OS.
        # Per-service datasets can be carved out later with `zfs create` without
        # reformatting, once it is clear which ones actually need it.
        var-lib = {
          type = "zfs_fs";
          mountpoint = "/var/lib";
        };
        # Bulk data: what the old host kept on its second 200GB LVM volume as
        # /mnt/jellyfin-media (media, the attic cache, archive dumps). Snapshotting
        # it would be expensive and pointless — it is either huge, re-downloadable,
        # or already content-addressed.
        srv = {
          type = "zfs_fs";
          mountpoint = "/srv";
          options."com.sun:auto-snapshot" = "false";
        };
        home = {
          type = "zfs_fs";
          mountpoint = "/home";
        };
      };
    };
  };
}
