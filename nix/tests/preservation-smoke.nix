{
  pkgs,
  preservation,
  user,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "dotfiles-preservation-smoke";

  nodes.machine =
    { lib, ... }:
    {
      imports = [ preservation.nixosModules.default ];

      # preservation requires systemd initrd (assertion in module.nix).
      boot.initrd.systemd.enable = true;

      preservation.enable = true;
      preservation.preserveAt."/persistent" = {
        directories = [
          "/etc/NetworkManager/system-connections"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/lib/sbctl"
          "/var/lib/tailscale"
        ];
        # Persist SSH host keys as individual key files via symlink + configureParent,
        # rather than "bind mounting the whole /etc/ssh directory".
        # Covering all of /etc/ssh with an empty volume would hide the NixOS-generated
        # sshd_config etc. and prevent sshd from starting (the upstream-recommended practice).
        files = [
          {
            file = "/etc/ssh/ssh_host_rsa_key";
            how = "symlink";
            configureParent = true;
          }
          {
            file = "/etc/ssh/ssh_host_ed25519_key";
            how = "symlink";
            configureParent = true;
          }
        ];
        users.${user.username}.directories = [
          ".config/sops/age"
          ".local/share/atuin"
          ".local/share/zoxide"
        ];
      };

      networking.networkmanager.enable = true;
      services.openssh.enable = true;
      users.users.${user.username} = {
        isNormalUser = true;
        createHome = true;
      };

      # Don't do persistent-disk verification of the machine-id commit in the VM.
      systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

      # Make persistent storage a real filesystem on a real block device (same approach as
      # upstream's tests/basic.nix). tmpfs is volatile and inappropriate as the backing for a
      # "persistent" volume, and mount handoff under neededForBoot + initrd systemd tends to be unstable.
      # With a real fs, /persistent reliably becomes a mountpoint.
      virtualisation = {
        memorySize = 2048;
        emptyDiskImages = [ 512 ];
        fileSystems."/persistent" = {
          device = "/dev/vdb";
          fsType = "ext4";
          autoFormat = true;
          neededForBoot = true;
        };
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Persistent storage is mounted.
    machine.succeed("mountpoint /persistent")

    # The system directory targeted for persistence is actually a bind mount.
    machine.succeed("mountpoint /var/lib/nixos")

    # sshd starts and the host key lives on the persistent volume via preservation.
    machine.wait_for_unit("sshd.service")
    machine.succeed("test -L /etc/ssh/ssh_host_ed25519_key")
    machine.succeed("test -s /persistent/etc/ssh/ssh_host_ed25519_key")

    # The user-specific persistent directory is created on the persistent volume.
    machine.succeed("test -d /persistent/home/${user.username}/.config/sops/age")

    # Writes to a persistence-targeted directory are reflected on the persistent volume.
    machine.succeed("touch /var/lib/nixos/preservation-smoke")
    machine.succeed("test -e /persistent/var/lib/nixos/preservation-smoke")
  '';
}
