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

    # Pre-built nix-index database shared by macOS, NixOS, WSL, and Linux HM.
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    agent-skills.url = "github:Kyure-A/agent-skills-nix";
    agent-skills.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS の Secure Boot 対応 (署名付き UKI)。nixos-laptop でのみ使用。
    lanzaboote.url = "github:nix-community/lanzaboote/v1.1.0";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs-nixos";

    # disko: 宣言的ディスクレイアウト。nixos-laptop の LUKS root のみ管理 (dual-boot 安全のため)。
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-nixos";

    # コード品質: pre-commit フック宣言 + treefmt (nix fmt)
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Flake出力を段階的にモジュール化。まずper-system出力から移行する。
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    # Homebrew caskをNix derivationとして扱う試験導入。brew-apiは鮮度を分離更新する。
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
    brew-nix.url = "github:BatteredBunny/brew-nix";
    brew-nix.inputs.brew-api.follows = "brew-api";
    brew-nix.inputs.nixpkgs.follows = "nixpkgs";
    brew-nix.inputs.nix-darwin.follows = "nix-darwin";
  };

  outputs =
    inputs@{
      nixpkgs,
      nixpkgs-nixos,
      nix-darwin,
      home-manager,
      nix-index-database,
      agent-skills,
      sops-nix,
      lanzaboote,
      disko,
      git-hooks,
      treefmt-nix,
      flake-parts,
      brew-nix,
      ...
    }:
    let
      system = "aarch64-darwin";
      # standalone Home Managerで使う公式プロプライエタリCLIだけを限定許可。
      # nix-darwin側のpkgs設定とは別インスタンスなので、ここにも必要。
      mkPkgs =
        targetSystem:
        import nixpkgs {
          system = targetSystem;
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "unity-cli";
          overlays = nixpkgs.lib.optionals (targetSystem == "aarch64-darwin") [
            brew-nix.overlays.default
          ];
        };
      mkWslPkgs =
        targetSystem:
        import nixpkgs {
          system = targetSystem;
          config.allowUnfreePredicate =
            pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "claude-code"
              "unity-cli"
            ];
        };
      pkgs = mkPkgs system;
      user = import ./user.nix;
      commonSpecialArgs = {
        inherit user;
        nixIndexDatabase = nix-index-database;
        agentSkills = agent-skills;
      };

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
          # 整形は per-file の nixfmt を使う (flake が nix/ にあるため
          # treefmt フックは git ルートから root 検出に失敗する。treefmt は nix fmt 専用)。
          nixfmt.enable = true;
          # statix は repeated_keys 等が module 記述と相性悪く、--config パスが
          # flake/git-root で一意にできないため enforced から除外。
          # 手動チェックは `nix run nixpkgs#statix -- check nix` で可能。
          deadnix = {
            enable = true; # nix 未使用コード
            settings.noLambdaPatternNames = true; # { lib, ... } 等の未使用引数は許容
          };
          shellcheck = {
            enable = true; # shell スクリプト lint (.shellcheckrc に従う)
            excludes = [
              # sketchybar 設定群は流儀として意図的な word splitting が多く別扱い
              # (手動チェック: nix develop ./nix -c shellcheck configs/wm/sketchybar/...)
              "configs/wm/sketchybar/.*"
              # direnv ファイルは shebang なし・direnv stdlib 前提
              "\\.envrc$"
              # macmini AI コマンド群は zsh (shellcheck は zsh 非対応 SC1071)
              "configs/macmini/bin/.*"
              # macmini 構築時の一発スクリプトのアーカイブ (歴史的資料、style 改修しない)
              "configs/macmini/setup-scripts/.*"
            ];
          };
          gitleaks = {
            enable = true;
            name = "gitleaks";
            entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged --no-banner --redact";
            pass_filenames = false;
          };
        };
      };

      perSystemOutputs = flake-parts.lib.mkFlake { inherit inputs; } {
        systems = [
          system
          "aarch64-linux"
          "x86_64-linux"
        ];

        perSystem =
          {
            system,
            lib,
            ...
          }:
          let
            isDarwinWorkstation = system == "aarch64-darwin";
            systemPkgs = if isDarwinWorkstation then pkgs else nixpkgs.legacyPackages.${system};
          in
          {
            formatter = if isDarwinWorkstation then treefmtEval.config.build.wrapper else systemPkgs.nixfmt;
            packages = {
              unity-cli = systemPkgs.callPackage ./pkgs/unity-cli.nix { };
            }
            // lib.optionalAttrs isDarwinWorkstation {
              lazy2nix = systemPkgs.writeShellApplication {
                name = "lazy2nix";
                runtimeInputs = [
                  systemPkgs.bun
                  systemPkgs.git
                  systemPkgs.neovim
                  systemPkgs.nix
                ];
                text = ''
                  repo="$(${systemPkgs.git}/bin/git rev-parse --show-toplevel)"
                  exec ${systemPkgs.bun}/bin/bun "$repo/configs/editors/nvim/lazy2nix/generate.ts"
                '';
              };
              slk = systemPkgs.callPackage ./pkgs/slk.nix { };
            }
            // lib.optionalAttrs (!isDarwinWorkstation) {
              remote-env = systemPkgs.buildEnv {
                name = "remote-env";
                paths = remoteTools systemPkgs;
              };
            };
          }
          // lib.optionalAttrs isDarwinWorkstation {
            checks.pre-commit = preCommit;
            devShells.default = systemPkgs.mkShell {
              inherit (preCommit) shellHook;
              buildInputs = preCommit.enabledPackages ++ [
                systemPkgs.shellcheck
                systemPkgs.statix
                systemPkgs.stylua
                systemPkgs.taplo
                systemPkgs.yq-go
                systemPkgs.jq
                systemPkgs.just
                systemPkgs.bun
              ];
            };
          };
      };
    in
    {
      # システム設定: sudo darwin-rebuild switch --flake .#<username>
      darwinConfigurations.${user.username} = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          inherit user;
          brewNix = brew-nix;
        };
        modules = [ ./hosts/darwin.nix ];
      };

      # ヘッドレス LLM ワーカー (M4 Mac mini / 24GB):
      #   sudo darwin-rebuild switch --flake .#macmini
      # darwin.nix と darwin-common.nix を共有しつつ、GUI cask を積まず
      # Ollama を launchd で常駐させる最小構成 (hosts/macmini.nix)。
      darwinConfigurations.macmini = nix-darwin.lib.darwinSystem {
        inherit system; # aarch64-darwin 共通
        specialArgs = { inherit user; };
        modules = [
          ./hosts/macmini.nix
          # workstation と同じ common.nix (フル CLI/zsh/XDG) + macmini.nix (ccm/AI
          # スタック配線)。sops は積まない (age 鍵を macmini に持ち込まない方針)。
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-bak";
            home-manager.extraSpecialArgs = commonSpecialArgs;
            home-manager.users.${user.username} = {
              imports = [
                ./home/common.nix
                ./home/macmini.nix
              ];
            };
          }
        ];
      };

      # NixOS 実機 (Windows デュアルブート): sudo nixos-rebuild switch --flake .#nixos-laptop
      # home-manager を NixOS モジュールとして組み込み、macOS / WSL と同じ
      # home/common.nix + home/linux.nix をユーザー設定として共有する。
      #
      # hosts/nixos-laptop-hardware.nix は実機で `nixos-generate-config` が吐く
      # マシン固有ファイル。それが存在するまでは出力ごと生やさず、Mac 上の
      # `nix flake check` / pre-commit が import 失敗で落ちないようにする。
      nixosConfigurations =
        nixpkgs-nixos.lib.optionalAttrs (builtins.pathExists ./hosts/nixos-laptop-hardware.nix) {
          "nixos-laptop" = nixpkgs-nixos.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit user; };
            modules = [
              ./hosts/nixos-laptop.nix
              lanzaboote.nixosModules.lanzaboote
              disko.nixosModules.disko
              ./hosts/nixos-laptop-disk.nix
              # 実行時の fileSystems/luks は生成 hardware-configuration.nix に任せ、
              # disko は「インストール時のフォーマット/マウントツール」としてのみ使う。
              { disko.enableConfig = false; }
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs = commonSpecialArgs;
                home-manager.users.${user.username} = {
                  imports = [
                    ./home/common.nix
                    ./home/linux.nix
                    ./home/hyprland.nix # Hyprland リック (nixos-laptop 専用)
                    ./home/dev.nix # direnv 等の開発環境
                    ./home/restic-backup-linux.nix # restic (systemd user timer)
                    sops-nix.homeManagerModules.sops
                    ./home/secrets.nix
                    ./home/workstation.nix
                  ];
                };
              }
            ];
          };
        }
        // {

          # 実機固有hardware-configurationを公開せず、共通NixOS設定をCI評価する構成。
          "nixos-laptop-ci" = nixpkgs-nixos.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {
              inherit user;
              hardwareConfig = ./hosts/nixos-laptop-hardware-ci.nix;
            };
            modules = [
              ./hosts/nixos-laptop.nix
              lanzaboote.nixosModules.lanzaboote
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs = commonSpecialArgs;
                home-manager.users.${user.username}.imports = [
                  ./home/common.nix
                  ./home/linux.nix
                  ./home/hyprland.nix
                  ./home/dev.nix
                  ./home/workstation.nix
                ];
              }
            ];
          };
        };

      # disko CLI 用 (ハード設定ファイル不要・guard 外)。インストール時に
      #   sudo disko --mode destroy,format,mount --flake <repo>/nix#nixos-laptop
      # で LUKS root パーティションだけを宣言的にフォーマット/マウントする。
      diskoConfigurations.nixos-laptop = import ./hosts/nixos-laptop-disk.nix;

      # macOS ユーザー設定: home-manager switch --flake .#<username>
      homeConfigurations.${user.username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = commonSpecialArgs;
        modules = [
          ./home/common.nix
          ./home/darwin.nix
          ./home/restic-backup.nix
          ./home/rclone-mount.nix
          ./home/maintenance.nix
          sops-nix.homeManagerModules.sops
          ./home/secrets.nix
          ./home/mopidy.nix
          ./home/workstation.nix
        ];
      };

      # WSL2 ユーザー設定: home-manager switch --flake .#<username>-wsl
      # Lab PC 等の Windows + WSL2 環境で使う
      homeConfigurations."${user.username}-wsl" =
        let
          wslSystem = "x86_64-linux";
          wslPkgs = mkWslPkgs wslSystem;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = wslPkgs;
          extraSpecialArgs = commonSpecialArgs;
          modules = [
            ./home/common.nix
            ./home/linux.nix
            ./home/wsl.nix
            sops-nix.homeManagerModules.sops
            ./home/secrets.nix
            ./home/workstation.nix
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
          wslPkgs = mkWslPkgs wslSystem;
          osUser = builtins.getEnv "USER";
          labUser = user // (if osUser != "" then { username = osUser; } else { });
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = wslPkgs;
          extraSpecialArgs = {
            user = labUser;
            nixIndexDatabase = nix-index-database;
            agentSkills = agent-skills;
          };
          modules = [
            ./home/common.nix
            ./home/linux.nix
            ./home/wsl.nix
            sops-nix.homeManagerModules.sops
            ./home/secrets.nix
            ./home/workstation.nix
          ];
        };

      # Linux サーバー / 自宅 NUC / VPS 用: .#<username>-linux
      # 純 Linux (WSL interop なし)。aarch64 / x86_64 両対応
      homeConfigurations."${user.username}-linux" =
        let
          linuxSystem = "x86_64-linux";
          linuxPkgs = mkPkgs linuxSystem;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = linuxPkgs;
          extraSpecialArgs = commonSpecialArgs;
          modules = [
            ./home/common.nix
            ./home/linux.nix
            sops-nix.homeManagerModules.sops
            ./home/secrets.nix
            ./home/workstation.nix
          ];
        };
      homeConfigurations."${user.username}-linux-aarch64" =
        let
          linuxSystem = "aarch64-linux";
          linuxPkgs = mkPkgs linuxSystem;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = linuxPkgs;
          extraSpecialArgs = commonSpecialArgs;
          modules = [
            ./home/common.nix
            ./home/linux.nix
            sops-nix.homeManagerModules.sops
            ./home/secrets.nix
            ./home/workstation.nix
          ];
        };

    }
    // perSystemOutputs;
}
