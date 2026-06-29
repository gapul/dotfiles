{
  description = "macOS dotfiles managed with Nix flakes (nix-darwin + home-manager + sops-nix)";

  # NOTE: キャッシュ (cache.nixos.org / nix-community / flakehub) は flake の nixConfig でなく
  # system の /etc/nix/nix.custom.conf (hosts/darwin.nix の postActivation) で宣言している。
  # flake nixConfig だと nh 実行毎に "Using saved setting..." が出る上、任意 flake 設定を
  # 信頼する方向なので、最小権限で system 側に置く方針。

  inputs = {
    # 26.05 系で揃える (nix-darwin#1462 'USER is root' regression 回避)
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    # NixOS 実機 (Windows デュアルブートの HP ノート, x86_64) 用。
    # darwin 系チャンネルと分けて nixos キャッシュにきれいに当てる。
    nixpkgs-nixos.url = "github:NixOS/nixpkgs/nixos-26.05";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS の Secure Boot 対応 (署名付き UKI)。nixos-laptop でのみ使用。
    lanzaboote.url = "github:nix-community/lanzaboote/v0.4.2";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs-nixos";

    # コード品質: pre-commit フック宣言 + treefmt (nix fmt)
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-nixos,
      nix-darwin,
      home-manager,
      sops-nix,
      lanzaboote,
      git-hooks,
      treefmt-nix,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      user = import ./user.nix;

      # SSH 接続先で rootless Nix (nix-portable) から実行する
      # ツール一式。Linux x86_64 / aarch64 両対応。
      remoteTools =
        pkgs': with pkgs'; [
          neovim
          yazi
          zellij
          git
          ripgrep
          fd
          fzf
          bat
          eza
          zoxide
          curl
          wget
        ];
      remoteSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      # nix fmt: nixfmt(nix) + shfmt(shell) を束ねる
      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.shfmt.enable = true;
        settings.formatter.shfmt.options = [
          "-i"
          "2"
        ]; # 2-space (CLAUDE.md 準拠)
      };

      # pre-commit フックを nix で宣言。src は nix/ (flake サブツリー)。
      # scripts/ 等リポ全体は `pre-commit run --all-files` を git ルートで回してカバー。
      preCommit = git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          # 整形は per-file の nixfmt-rfc-style を使う (flake が nix/ にあるため
          # treefmt フックは git ルートから root 検出に失敗する。treefmt は nix fmt 専用)。
          nixfmt-rfc-style.enable = true;
          # statix は repeated_keys 等が module 記述と相性悪く、--config パスが
          # flake/git-root で一意にできないため enforced から除外。
          # 手動チェックは `nix run nixpkgs#statix -- check nix` で可能。
          deadnix = {
            enable = true; # nix 未使用コード
            settings.noLambdaPatternNames = true; # { lib, ... } 等の未使用引数は許容
          };
          # shellcheck は既存スクリプトに warning が多く、gate にすると commit を阻む。
          # enforced からは外し、devShell に shellcheck を入れて手動利用可とする
          # (`nix develop ./nix -c shellcheck scripts/*.sh`)。スクリプト整備後に有効化検討。
          gitleaks = {
            enable = true;
            name = "gitleaks";
            entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged --no-banner --redact";
            pass_filenames = false;
          };
        };
      };
    in
    {
      # システム設定: sudo darwin-rebuild switch --flake .#<username>
      darwinConfigurations.${user.username} = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit user; };
        modules = [ ./hosts/darwin.nix ];
      };

      # NixOS 実機 (Windows デュアルブート): sudo nixos-rebuild switch --flake .#nixos-laptop
      # home-manager を NixOS モジュールとして組み込み、macOS / WSL と同じ
      # home/common.nix + home/linux.nix をユーザー設定として共有する。
      #
      # hosts/nixos-laptop-hardware.nix は実機で `nixos-generate-config` が吐く
      # マシン固有ファイル。それが存在するまでは出力ごと生やさず、Mac 上の
      # `nix flake check` / pre-commit が import 失敗で落ちないようにする。
      nixosConfigurations =
        nixpkgs-nixos.lib.optionalAttrs (builtins.pathExists ./hosts/nixos-laptop-hardware.nix)
          {
            "nixos-laptop" = nixpkgs-nixos.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = { inherit user; };
              modules = [
                ./hosts/nixos-laptop.nix
                lanzaboote.nixosModules.lanzaboote
                home-manager.nixosModules.home-manager
                {
                  home-manager.useGlobalPkgs = true;
                  home-manager.useUserPackages = true;
                  home-manager.extraSpecialArgs = { inherit user; };
                  home-manager.users.${user.username} = {
                    imports = [
                      ./home/common.nix
                      ./home/linux.nix
                      ./home/hyprland.nix # Hyprland リック (nixos-laptop 専用)
                      ./home/dev.nix # direnv 等の開発環境
                      ./home/restic-backup-linux.nix # restic (systemd user timer)
                      sops-nix.homeManagerModules.sops
                    ];
                  };
                }
              ];
            };
          };

      # macOS ユーザー設定: home-manager switch --flake .#<username>
      homeConfigurations.${user.username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit user; };
        modules = [
          ./home/common.nix
          ./home/darwin.nix
          ./home/restic-backup.nix
          ./home/rclone-mount.nix
          ./home/maintenance.nix
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

      # Lab PC (Mac の username と違う OS username を持つ WSL2 環境) 用:
      # 公開 repo に個人情報を残さないため、username は実行時の $USER から取る。
      # .gitignore したファイルは flake source に含まれないので user.local.nix
      # パターンは機能せず、builtins.getEnv "USER" + --impure フラグで対応。
      #
      # 使い方:
      #   nix run --impure github:nix-community/home-manager -- \
      #     switch --flake ~/.dotfiles/nix#labpc-wsl
      homeConfigurations."labpc-wsl" =
        let
          wslSystem = "x86_64-linux";
          wslPkgs = nixpkgs.legacyPackages.${wslSystem};
          osUser = builtins.getEnv "USER";
          labUser = user // (if osUser != "" then { username = osUser; } else { });
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = wslPkgs;
          extraSpecialArgs = {
            user = labUser;
          };
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

      # nix fmt
      formatter.${system} = treefmtEval.config.build.wrapper;

      # nix flake check で nix/ の整形・lint・secret を検査
      checks.${system}.pre-commit = preCommit;

      # nix develop: 入室で .git/hooks に pre-commit を導入
      devShells.${system}.default = pkgs.mkShell {
        inherit (preCommit) shellHook;
        # enforced フック + 手動/CI 用 lint ツール一式。
        # CI (check.yml の lint job) も `nix develop ./nix -c <tool>` で同じバージョンを使い、
        # ローカルと CI のバージョン差 (just --fmt の {{x}} vs {{ x }} 等) を防ぐ。
        buildInputs = preCommit.enabledPackages ++ [
          pkgs.shellcheck # shell lint
          pkgs.statix # nix アンチパターン
          pkgs.stylua # lua 整形 (nvim 設定)
          pkgs.taplo # toml 構文/整形
          pkgs.yq-go # yaml 構文検証
          pkgs.jq # json 構文検証
          pkgs.just # Justfile (ローカル/CI でバージョン統一)
        ];
      };
    };
}
