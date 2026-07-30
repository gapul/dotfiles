_:
# disko declarative disk layout (nixos-laptop).
#
# ⚠️ dual-boot safety policy: what is managed here is **only the single Linux partition
#    manually created in free space (= LUKS root)**. The whole GPT, Windows and ESP are never touched.
#    `device` must always point to that single partition (e.g. /dev/nvme0n1p5).
#    Pointing it at the whole disk (/dev/nvme0n1) or at Windows/ESP is destructive.
#
# Usage (installer live environment):
#   1. Create one "Linux filesystem" partition in free space with cfdisk
#   2. Replace the device below with the real value (by-id recommended; check with lsblk -o NAME,SIZE,FSTYPE,PATH)
#   3. sudo disko --mode destroy,format,mount --flake <repo>/nix#nixos-laptop
#      → LUKS-encrypts only that partition + ext4 + mounts to /mnt
#   4. ESP is outside disko management. Mount it manually with `mount <ESP> /mnt/boot` (do not format)
#
# enableConfig=false is specified on the flake side (nixos module context). Leave the runtime
# fileSystems / luks.devices to the generated hardware-configuration.nix to avoid double definition.
{
  disko.devices.disk.cryptroot = {
    type = "disk";
    # ↓ Replace with the real machine's single Linux partition (never the whole disk/Windows/ESP)
    device = "/dev/disk/by-id/REPLACE_WITH_ROOT_PARTITION";
    content = {
      type = "luks";
      name = "cryptroot"; # matches crypttabExtraOpts in hosts/nixos-laptop.nix
      settings.allowDiscards = true; # allow SSD TRIM
      content = {
        type = "filesystem";
        format = "ext4";
        mountpoint = "/";
      };
    };
  };
}
