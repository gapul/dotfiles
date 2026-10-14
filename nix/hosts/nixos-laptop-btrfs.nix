{ lib, ... }:
# cryptroot as Btrfs, offered as the "btrfs" boot entry while the move from ext4 is under way.
# The normal entries still mount it as ext4, so this can be tried and the old layout kept until
# it is known to work; once it does, these mounts move into nixos-laptop-hardware.nix and the
# specialisation goes.
#
# The move itself is done from the maint boot (nixos-laptop-maint.nix), on the unlocked but
# unmounted cryptroot:
#   btrfs-convert /dev/mapper/cryptroot     (in place; the old ext4 stays as ext2_saved/image,
#                                            and `btrfs-convert -r` goes back while it does)
#   mount it at /mnt; snapshot the top level as @; move home, nix and var/log out of @ into
#   their own subvolumes with `cp -a --reflink=always` (shares the data, copies nothing)
# Subvolumes, all on the one LUKS device:
#   @      /          @home  /home
#   @nix   /nix       @log   /var/log
let
  device = "/dev/mapper/cryptroot";
  # zstd level 1: compresses what is written from now on at little CPU cost. noatime: no write
  # on every read, which on a copy-on-write filesystem also means no metadata churn.
  options = subvol: [
    "subvol=${subvol}"
    "compress=zstd:1"
    "noatime"
  ];
in
{
  specialisation.btrfs.configuration = {
    fileSystems."/" = {
      fsType = lib.mkForce "btrfs";
      options = lib.mkForce (options "@");
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
    fileSystems."/var/log" = {
      inherit device;
      fsType = "btrfs";
      options = options "@log";
      neededForBoot = true;
    };
  };
}
