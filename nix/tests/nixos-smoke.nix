{
  pkgs,
  user,
  home-manager,
  lanzaboote,
  sops-nix,
  commonSpecialArgs,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "dotfiles-nixos-smoke";

  node.specialArgs = {
    inherit user;
    inherit (commonSpecialArgs) nixpkgsUnstable;
    hardwareConfig = ./nixos-test-hardware.nix;
  };
  node.pkgsReadOnly = false;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../hosts/nixos-laptop.nix
        lanzaboote.nixosModules.lanzaboote
        sops-nix.nixosModules.sops # hosts/nixos-laptop-wifi.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = commonSpecialArgs;
          home-manager.users.${user.username}.imports = [
            ../home/common.nix
            ../home/linux.nix
            # Not hyprland.nix: it now needs stylix, darkman and the rest of the desktop modules,
            # and the script below only checks system-level state.
            ../home/dev.nix
            ../home/workstation.nix
          ];
        }
      ];

      boot.lanzaboote.enable = lib.mkForce false;
      # The maint boot (hosts/nixos-laptop-maint.nix) needs the laptop's LUKS device and an initrd
      # secret only Lanzaboote carries; neither exists here, and the script does not use it.
      specialisation.maint = lib.mkForce { configuration = { }; };
      # The test driver reads the serial console; the laptop keeps it quiet for Plymouth.
      boot.consoleLogLevel = lib.mkForce 7;
      boot.initrd.luks.devices = lib.mkForce { };
      boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
      services.greetd.enable = lib.mkForce false;
      services.displayManager.regreet.enable = lib.mkForce false; # needs greetd's greeter user
      services.fprintd.enable = lib.mkForce false;
      services.fwupd.enable = lib.mkForce false;
      services.tailscale.enable = lib.mkForce false;
      # The VM has no laptop host key to open secrets/nixos-laptop.yaml with, so drop the
      # secret and the env file NetworkManager would wait on. The profiles still evaluate.
      sops.secrets = lib.mkForce { };
      networking.networkmanager.ensureProfiles.environmentFiles = lib.mkForce [ ];
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
