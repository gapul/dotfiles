# The ECS "System" = host composer. Unifies the boilerplate for assembling
# Components/roles (home/, modules/) onto an Entity (hosts/). roles (component bundles) are defined in flake.nix's let block.
#   darwin: nix-darwin system config (+ optionally home-manager integration)
#   home  : standalone home-manager config
{
  nixpkgs,
  nix-darwin,
  home-manager,
  nix-homebrew,
  user,
  system,
  commonSpecialArgs,
  mkPkgs,
  mkWslPkgs,
}:
{
  darwin =
    {
      host,
      homeModules ? [ ],
      # Where home.packages land. true puts them in /etc/profiles/per-user/<user>, which is the
      # nix-darwin default and right for a host set up that way from the start. The workstation
      # was standalone home-manager for years, so its ~/.local/state/nix/profile is what PATH
      # points at and what 757 binaries live in; folding it in with true would silently move all
      # of them somewhere PATH does not look. It keeps false and its existing profile.
      useUserPackages ? true,
      specialArgs ? {
        inherit user;
      },
    }:
    nix-darwin.lib.darwinSystem {
      inherit system specialArgs;
      modules = [
        # Every darwin host in this repo drives Homebrew, so the installation manager belongs
        # here rather than in one host file (the asymmetry between hosts is what bites later).
        nix-homebrew.darwinModules.nix-homebrew
        host
      ]
      ++ nixpkgs.lib.optionals (homeModules != [ ]) [
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = useUserPackages;
          home-manager.backupFileExtension = "hm-bak";
          home-manager.extraSpecialArgs = commonSpecialArgs;
          home-manager.users.${user.username} = {
            imports = homeModules;
          };
        }
      ];
    };

  home =
    {
      targetSystem ? system,
      wsl ? false,
      modules,
      specialArgs ? commonSpecialArgs,
    }:
    home-manager.lib.homeManagerConfiguration {
      pkgs = (if wsl then mkWslPkgs else mkPkgs) targetSystem;
      extraSpecialArgs = specialArgs;
      inherit modules;
    };
}
