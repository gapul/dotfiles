# ECS の「System」= ホスト合成器。Entity(hosts/) に Component/role(home/, modules/) を
# 組み付ける定型を一本化する。roles (component 束) は flake.nix の let 側で定義。
#   darwin: nix-darwin システム構成 (+ 任意で home-manager 統合)
#   home  : standalone home-manager 構成
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
