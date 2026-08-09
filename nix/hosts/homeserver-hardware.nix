{ lib, ... }:
{
  # Bosgame DNB20 mini PC: Intel CPU, UEFI, one NVMe, Intel I226-V NIC (igc).
  #
  # Written by hand and committed, rather than being the output of
  # nixos-generate-config that has to be dropped onto the machine: disko owns the
  # disk layout and generates fileSystems, so the only machine-specific facts left
  # are the initrd modules and the CPU vendor. That means this host has no
  # uncommitted piece and CI builds exactly what gets installed.
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];

  hardware.cpu.intel.updateMicrocode = true;
  # The igc driver for the I226-V NIC lives in the kernel, but the box also wants
  # redistributable firmware blobs for its other bits.
  hardware.enableRedistributableFirmware = true;

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = "x86_64-linux";
}
