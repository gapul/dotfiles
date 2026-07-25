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

      boot.initrd.systemd.enable = true;
      preservation.enable = true;
      preservation.preserveAt."/persistent" = {
        directories = [
          "/etc/NetworkManager/system-connections"
          "/etc/ssh"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/lib/sbctl"
          "/var/lib/tailscale"
        ];
        users.${user.username}.directories = [
          ".config/sops/age"
          ".local/share/atuin"
          ".local/share/zoxide"
        ];
      };

      fileSystems."/persistent" = {
        device = "none";
        fsType = "tmpfs";
        neededForBoot = true;
      };

      networking.networkmanager.enable = true;
      services.openssh.enable = true;
      users.users.${user.username} = {
        isNormalUser = true;
        createHome = true;
      };

      # VMではmachine-id commitの永続ディスク検証を行わない。
      systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];
      virtualisation.memorySize = 1024;
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mountpoint /persistent")
    machine.succeed("mountpoint /etc/ssh")
    machine.succeed("mountpoint /var/lib/nixos")
    machine.succeed("test -d /persistent/home/${user.username}/.config/sops/age")
    machine.succeed("touch /var/lib/nixos/preservation-smoke")
    machine.succeed("test -e /persistent/var/lib/nixos/preservation-smoke")
  '';
}
