# The ECS "System" = host composer. Unifies the boilerplate for assembling
# Components/roles (home/, modules/) onto an Entity (hosts/). roles (component bundles) are defined in flake.nix's let block.
#   darwin: nix-darwin system config (+ optionally home-manager integration)
#   home  : standalone home-manager config
{
  nixpkgs,
  nix-darwin,
  home-manager,
  nix-homebrew,
  brew-src,
  brewVersion,
  user,
  system,
  commonSpecialArgs,
  mkPkgs,
  self,
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
        # Every darwin host in this repo drives Homebrew, so the installation manager belongs
        # here rather than in one host file (the asymmetry between hosts is what bites later).
        nix-homebrew.darwinModules.nix-homebrew
        # flake.nix overrides nix-homebrew's brew-src, whose version label is hard-coded in
        # nix-homebrew; the label is what HOMEBREW_VERSION gets patched to, so it follows ours.
        {
          nix-homebrew.package = brew-src // {
            name = "brew-${brewVersion}";
            version = brewVersion;
          };
        }
        host
        # Record the dotfiles commit, so darwin-version.json says which commit is running.
        { system.configurationRevision = self.rev or self.dirtyRev or null; }
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
      modules,
      specialArgs ? commonSpecialArgs,
    }:
    home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs targetSystem;
      extraSpecialArgs = specialArgs;
      inherit modules;
    };
}
