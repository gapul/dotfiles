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
#   - write systemd-boot's LoaderEntryOneShot EFI variable (4a67b082-…) with the entry id
#     (`bootctl list`), as UTF-16LE after the 07000000 attribute bytes. `bootctl set-oneshot`
#     refuses, since the running system was booted by rEFInd, not systemd-boot;
#   - sudo efibootmgr --bootnext <systemd-boot's Boot####, "NixOS">
#   - sudo systemctl reboot
# The menu may still show; pick the "…-maint" entry. Then `ssh -p 2222 root@<address>`: the
# address is on screen, as DHCP in the initrd gets a different lease from the usual one.
# Nothing is unlocked or mounted; inside:
#   systemd-cryptsetup attach cryptroot /dev/disk/by-uuid/<uuid> - tpm2-device=auto,tpm2-pin=yes
# `systemctl reboot` from there goes back through rEFInd to the normal generation.
let
  hostKey = "/etc/secrets/initrd/ssh_host_ed25519_key";
in
{
  specialisation.maint.configuration = {
    # The normal boot is silent (quiet, splash, no cursor), which here left a black screen with
    # no way to tell whether the network came up. Show everything instead.
    boot.kernelParams = lib.mkForce [
      "rd.systemd.unit=maint.target"
      "root=fstab"
      "loglevel=7"
      "rd.systemd.show_status=true"
    ];
    boot.plymouth.enable = lib.mkForce false;

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
          # Any wired interface: in the initrd the adapter may not get its usual enp… name.
          networks."10-wired" = {
            matchConfig.Type = "ether";
            networkConfig.DHCP = "yes";
          };
        };
        services = {
          # The addresses on tty1, refreshed, so the screen says where to ssh to.
          maint-banner = {
            wantedBy = [ "maint.target" ];
            serviceConfig = {
              StandardOutput = "tty";
              TTYPath = "/dev/tty1";
              Restart = "always";
            };
            script = ''
              while :; do
                printf '\n== maint: ssh -p 2222 root@<address> | shell on Alt+F2 ==\n'
                ip -br addr
                sleep 10
              done
            '';
          };
          # A root shell on tty2 at the physical keyboard, for when the network does not come
          # up. Only in this boot entry; cryptroot stays locked until someone unlocks it.
          maint-shell = {
            wantedBy = [ "maint.target" ];
            serviceConfig = {
              ExecStart = "/bin/sh -l";
              StandardInput = "tty";
              StandardOutput = "tty";
              StandardError = "tty";
              TTYPath = "/dev/tty2";
              TTYReset = true;
              TTYVHangup = true;
              Restart = "always";
            };
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
