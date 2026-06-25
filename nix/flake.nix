{
  description = "macOS dotfiles managed with Nix flakes (nix-darwin + home-manager + sops-nix)";

  # Determinate環境でも vanilla 移行後でも同じキャッシュが効くよう、flake自身に宣言
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://cache.flakehub.com"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "cache.flakehub.com-4:Asi8qIv291s0aYLyH6IOnr5Kf6+OF14WVjkE6t3xMio="
      "cache.flakehub.com-5:zB96CRlL7tiPtzA9/WKyPkp3A2vqxqgdgyTVNGShPDU="
      "cache.flakehub.com-6:W4EGFwAGgBj3he7c5fNh9NkOXw0PUVaxygCVKeuvaqU="
      "cache.flakehub.com-7:mvxJ2DZVHn/kRxlIaxYNMuDG1OvMckZu32um1TadOR8="
      "cache.flakehub.com-8:moO+OVS0mnTjBTcOUh2kYLQEd59ExzyoW1QgQ8XAARQ="
      "cache.flakehub.com-9:wChaSeTI6TeCuV/Sg2513ZIM9i0qJaYsF+lZCXg0J6o="
      "cache.flakehub.com-10:2GqeNlIp6AKp4EF2MVbE1kBOp9iBSyo0UPR9KoR0o1Y="
    ];
  };

  inputs = {
    # 26.05 系で揃える (nix-darwin#1462 'USER is root' regression 回避)
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-darwin, home-manager, sops-nix, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      user = import ./user.nix;

      # SSH 接続先で rootless Nix (nix-portable) から実行する
      # ツール一式。Linux x86_64 / aarch64 両対応。
      remoteTools = pkgs': with pkgs'; [
        neovim yazi zellij
        git ripgrep fd fzf bat eza zoxide
        curl wget
      ];
      remoteSystems = [ "aarch64-linux" "x86_64-linux" ];
    in
    {
      # システム設定: sudo darwin-rebuild switch --flake .#<username>
      darwinConfigurations.${user.username} = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit user; };
        modules = [ ./hosts/darwin.nix ];
      };

      # macOS ユーザー設定: home-manager switch --flake .#<username>
      homeConfigurations.${user.username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit user; };
        modules = [
          ./home/common.nix
          ./home/darwin.nix
          sops-nix.homeManagerModules.sops
        ];
      };

      # WSL2 ユーザー設定: home-manager switch --flake .#<username>-wsl
      # Lab PC 等の Windows + WSL2 環境で使う
      homeConfigurations."${user.username}-wsl" =
        let
          wslSystem = "x86_64-linux";
          wslPkgs = nixpkgs.legacyPackages.${wslSystem};
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = wslPkgs;
          extraSpecialArgs = { inherit user; };
          modules = [
            ./home/common.nix
            ./home/linux.nix
            ./home/wsl.nix
            sops-nix.homeManagerModules.sops
          ];
        };

      # Linux サーバー / 自宅 NUC / VPS 用: .#<username>-linux
      # 純 Linux (WSL interop なし)。aarch64 / x86_64 両対応
      homeConfigurations."${user.username}-linux" =
        let
          linuxSystem = "x86_64-linux";
          linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = linuxPkgs;
          extraSpecialArgs = { inherit user; };
          modules = [
            ./home/common.nix
            ./home/linux.nix
            sops-nix.homeManagerModules.sops
          ];
        };
      homeConfigurations."${user.username}-linux-aarch64" =
        let
          linuxSystem = "aarch64-linux";
          linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = linuxPkgs;
          extraSpecialArgs = { inherit user; };
          modules = [
            ./home/common.nix
            ./home/linux.nix
            sops-nix.homeManagerModules.sops
          ];
        };

      # Remote (Linux) bundle: nssh から `nix-portable nix shell .#remote-env` で使う
      packages = nixpkgs.lib.genAttrs remoteSystems (sys: {
        remote-env = nixpkgs.legacyPackages.${sys}.buildEnv {
          name = "remote-env";
          paths = remoteTools nixpkgs.legacyPackages.${sys};
        };
      });
    };
}
