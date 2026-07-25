{
  pkgs,
  user,
  home-manager,
  lanzaboote,
  commonSpecialArgs,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "dotfiles-nixos-smoke";

  node.specialArgs = {
    inherit user;
    hardwareConfig = ./nixos-test-hardware.nix;
  };
  node.pkgsReadOnly = false;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../hosts/nixos-laptop.nix
        lanzaboote.nixosModules.lanzaboote
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = commonSpecialArgs;
          home-manager.users.${user.username}.imports = [
            ../home/common.nix
            ../home/linux.nix
            ../home/hyprland.nix
            ../home/dev.nix
            ../home/workstation.nix
          ];
        }
      ];

      boot.lanzaboote.enable = lib.mkForce false;
      boot.initrd.luks.devices = lib.mkForce { };
      boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
      services.greetd.enable = lib.mkForce false;
      services.fprintd.enable = lib.mkForce false;
      services.fwupd.enable = lib.mkForce false;
      services.tailscale.enable = lib.mkForce false;
      virtualisation.graphics = false;
      virtualisation.memorySize = 3072;
      users.users.${user.username}.initialPassword = "smoke-test";
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sshd.service")
    machine.succeed("id ${user.username}")
    machine.succeed("getent passwd ${user.username} | grep -q /bin/zsh")
    machine.succeed("test -x /run/current-system/sw/bin/git")
    machine.succeed("test -e /run/current-system/specialisation/safe")
    machine.succeed("systemctl is-enabled NetworkManager.service")
  '';
}
