{ lib, modulesPath, ... }:
{
  # Stand-in for the hardware-configuration.nix that nixos-generate-config emits on
  # the real machine, so `om ci` can evaluate and build the host config from a Mac.
  # Same trick as nixos-laptop-hardware-ci.nix.
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "nvme"
    "sd_mod"
  ];
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000003";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0000-0001";
    fsType = "vfat";
  };
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = "x86_64-linux";
}
