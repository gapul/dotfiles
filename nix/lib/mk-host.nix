# The ECS "System" = host composer. Unifies the boilerplate for assembling
# Components/roles (home/, modules/) onto an Entity (hosts/). roles (component bundles) are defined in flake.nix's let block.
#   darwin: nix-darwin system config (+ optionally home-manager integration)
#   home  : standalone home-manager config
{
  nixpkgs,
  nix-darwin,
  home-manager,
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
      specialArgs ? {
        inherit user;
      },
    }:
    nix-darwin.lib.darwinSystem {
      inherit system specialArgs;
      modules = [
        host
      ]
      ++ nixpkgs.lib.optionals (homeModules != [ ]) [
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
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
