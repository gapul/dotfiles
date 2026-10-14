{
  config,
  lib,
  pkgs,
  ...
}:
# A maintenance boot that stops in the initrd, before the root filesystem is mounted, and
# waits for ssh on the wired LAN. It exists for work that cannot be done on a mounted root
# (re-formatting cryptroot as Btrfs, fsck), done remotely from macmini rather than from a
# USB installer: the installer does not boot with Secure Boot on, and turning Secure Boot off
# changes PCR 7 and drops the TPM unlock.
#
# Reaching it, from a running system (rEFInd is first in the boot order and always boots the
# newest generation, so the one-shot has to go through systemd-boot):
#   sudo bootctl set-oneshot nixos-generation-<N>-specialisation-maint-<hash>.efi
#   sudo efibootmgr --bootnext <systemd-boot's Boot####>
#   sudo systemctl reboot
# then `ssh -p 2222 root@<laptop's LAN address>`. Nothing is unlocked or mounted; inside:
#   systemd-cryptsetup attach cryptroot /dev/disk/by-uuid/<uuid> - tpm2-device=auto,tpm2-pin=yes
# `systemctl reboot` from there goes back through rEFInd to the normal generation.
let
  hostKey = "/etc/secrets/initrd/ssh_host_ed25519_key";
in
{
  specialisation.maint.configuration = {
    boot.kernelParams = [ "rd.systemd.unit=maint.target" ];

    boot.initrd = {
      # The USB Ethernet adapter on the desk (ASIX AX88179 family, in NCM mode).
      availableKernelModules = [
        "cdc_ncm"
        "cdc_ether"
        "usbnet"
        "ax88179_178a"
      ];
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222; # not 22, so the client keeps a separate host key for it
          hostKeys = [ hostKey ];
          authorizedKeys = config.users.users.gapul.openssh.authorizedKeys.keys;
        };
      };
      systemd = {
        network = {
          enable = true;
          networks."10-wired" = {
            matchConfig.Name = "en*";
            networkConfig.DHCP = "yes";
          };
        };
        # Waits here instead of going on to unlock and mount the root filesystem.
        targets.maint = {
          description = "Maintenance: network and sshd, root left alone";
          wants = [
            "systemd-networkd.service"
            "sshd.service"
          ];
          after = [
            "systemd-networkd.service"
            "sshd.service"
          ];
          unitConfig.AllowIsolate = true;
        };
        # What the work needs, beyond the initrd's own systemd and util-linux.
        extraBin = {
          btrfs = "${pkgs.btrfs-progs}/bin/btrfs";
          btrfs-convert = "${pkgs.btrfs-progs}/bin/btrfs-convert";
          "mkfs.btrfs" = "${pkgs.btrfs-progs}/bin/mkfs.btrfs";
          e2fsck = "${pkgs.e2fsprogs}/bin/e2fsck";
          resize2fs = "${pkgs.e2fsprogs}/bin/resize2fs";
          rsync = "${pkgs.rsync}/bin/rsync";
          cp = "${pkgs.coreutils}/bin/cp";
          du = "${pkgs.coreutils}/bin/du";
          df = "${pkgs.coreutils}/bin/df";
          ip = "${pkgs.iproute2}/bin/ip";
        };
      };
    };
  };

  # The initrd's host key, made once on this machine (it is an initrd secret, not in the store).
  system.activationScripts.initrdSshHostKey = ''
    if [ ! -f ${hostKey} ]; then
      mkdir -p -m 700 "$(dirname ${hostKey})"
      ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f ${hostKey}
    fi
  '';
  environment.systemPackages = [ pkgs.efibootmgr ];
}
