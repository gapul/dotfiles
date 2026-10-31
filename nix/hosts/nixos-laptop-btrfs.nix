{ lib, ... }:
# cryptroot is Btrfs (since 2026-10-15), in subvolumes on the one LUKS device:
#   @      /          @home  /home
#   @nix   /nix       @log   /var/log
# nixos-laptop-hardware.nix is nixos-generate-config's and still says ext4, so the root mount
# is overridden here rather than edited there.
#
# It was moved by copying, not converting: the ext4 root went out to homeserver as a tar.zst
# from the maint boot (nixos-laptop-maint.nix), cryptroot's contents were re-made with
# mkfs.btrfs (LUKS and its TPM slot untouched) and the archive came back into the subvolumes.
# btrfs-convert was tried first and is not worth repeating: it took over an hour on the nix
# store's millions of names, and a snapshot of the converted tree corrupted its extent refs.
let
  device = "/dev/mapper/cryptroot";
  # zstd level 1: compresses what is written at little CPU cost (the restored 120 GB came to
  # 69 GiB). noatime: no write on every read, which on copy-on-write is metadata churn too.
  options = subvol: [
    "subvol=${subvol}"
    "compress=zstd:1"
    "noatime"
  ];
in
{
  # Loaded before udev sees cryptroot. systemd's udev rule asks btrfs.ko whether the
  # filesystem is complete, and with the module not yet loaded the answer is "not ready", so
  # the device unit never becomes ready and the mount that would load the module never runs:
  # the first boot sat at "A start job is running for /dev/mapper/cryptroot (no limit)".
  boot.initrd.kernelModules = [ "btrfs" ];

  fileSystems."/" = {
    fsType = lib.mkForce "btrfs";
    # Merged, not forced: NixOS adds x-initrd.mount to the root entry, and forcing the list
    # dropped it, so the initrd never mounted /sysroot and the system came up on its empty RAM
    # root with only /nix and /home on disk (generation 170).
    options = options "@";
  };
  fileSystems."/home" = {
    inherit device;
    fsType = "btrfs";
    options = options "@home";
  };
  fileSystems."/nix" = {
    inherit device;
    fsType = "btrfs";
    options = options "@nix";
    neededForBoot = true;
  };
  # Snapshots, which are why this is Btrfs. / and /home only: @nix is rebuilt from the flake,
  # and @log stays out so rolling the system back does not roll its logs back too.
  # snapper wants each config's .snapshots to be a subvolume; they were made by hand with
  # `btrfs subvolume create /.snapshots /home/.snapshots`.
  # Only the last 24 hourly snapshots are kept, so a deletion frees its space within a day.
  services.snapper.configs = {
    root = {
      SUBVOLUME = "/";
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 24;
      TIMELINE_LIMIT_DAILY = 0;
      TIMELINE_LIMIT_WEEKLY = 0;
      TIMELINE_LIMIT_MONTHLY = 0;
      TIMELINE_LIMIT_YEARLY = 0;
    };
    home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "gapul" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 24;
      TIMELINE_LIMIT_DAILY = 0;
      TIMELINE_LIMIT_WEEKLY = 0;
      TIMELINE_LIMIT_MONTHLY = 0;
      TIMELINE_LIMIT_YEARLY = 0;
    };
  };

  # Reads everything back against its checksums once a month; one device, so it finds damage
  # rather than repairing it.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # journald rewrites its files in place, which copy-on-write fragments badly (it warns at boot).
  # +C only takes effect on files created afterwards.
  systemd.tmpfiles.rules = [ "h /var/log/journal - - - - +C" ];
  # The default cap (10% of the filesystem, clamped to 4G) was full: weeks of desktop noise.
  services.journald.settings.Journal.SystemMaxUse = "1G";

  fileSystems."/var/log" = {
    inherit device;
    fsType = "btrfs";
    options = options "@log";
    neededForBoot = true;
  };
}
