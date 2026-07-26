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

    # Android (Termux) 上の Nix 環境。release ブランチは 24.05 で止まっているため
    # master を nixpkgs follows で使う (nix-on-droid の常套)。aarch64-linux。
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/master";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Mopidy ビルド時パッチ集は別リポジトリに分離 (dotfiles を 336 ファイル分軽量化)。
    # flake=false のソースとして取り込み、nix/lib/mopidy-env.nix の patchDir に渡す。
    mopidy-patches = {
      url = "github:gapul/mopidy-rmpc-patches";
      flake = false;
    };

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

    # 永続化対象を明示する NixOS module。まず VM smoke test のみで試し、
    # 実機へはデータ移行手順が固まるまで適用しない。
    preservation.url = "github:nix-community/preservation";

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
      nix-on-droid,
      mopidy-patches,
      nix-index-database,
      agent-skills,
      sops-nix,
      lanzaboote,
      disko,
      preservation,
      git-hooks,
      treefmt-nix,
      flake-parts,
      brew-nix,
      ...
    }:
    let
      system = "aarch64-darwin";

      # 上流 nixpkgs の一時的な破損を吸収する overlay。
      # pre-commit 4.5.1 の test_output_isatty が GitHub の macos-14 ランナーで
      # 決定的に落ちる (sandbox の isatty 挙動依存)。pytestCheckHook の
      # disabledTests でその1テストだけ deselect する (他テストと build は温存。
      # doCheck=false は pytestCheckPhase を止められず別環境で 127 を招くため不可)。
      overlayFixes = _final: prev: {
        pre-commit = prev.pre-commit.overridePythonAttrs (o: {
          disabledTests = (o.disabledTests or [ ]) ++ [ "test_output_isatty" ];
        });
      };

      # standalone Home Managerで使う公式プロプライエタリCLIだけを限定許可。
      # nix-darwin側のpkgs設定とは別インスタンスなので、ここにも必要。
      mkPkgs =
        targetSystem:
        import nixpkgs {
          system = targetSystem;
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "unity-cli";
          overlays = [
            overlayFixes
          ]
          ++ nixpkgs.lib.optionals (targetSystem == "aarch64-darwin") [
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
          overlays = [ overlayFixes ];
        };
      pkgs = mkPkgs system;
      user = import ./user.nix;
      commonSpecialArgs = {
        inherit user;
        nixIndexDatabase = nix-index-database;
        agentSkills = agent-skills;
        mopidyPatches = mopidy-patches;
      };

      # ECS の「System」= ホスト合成器 (darwin / home の定型を一本化)
      mkHost = import ./lib/mk-host.nix {
        inherit
          nixpkgs
          nix-darwin
          home-manager
          user
          system
          commonSpecialArgs
          mkPkgs
          mkWslPkgs
          ;
      };

      # ECS の「role」= component (home/*.nix) の束。ホストは roles を組み合わせるだけ。
      # 並び順は home.packages 等のリスト連結順に影響するため既存構成と同一に保つ。
      roles = rec {
        base = [ ./home/common.nix ];
        secrets = [
          sops-nix.homeManagerModules.sops
          ./home/secrets.nix
        ];
        station = [ ./home/workstation.nix ];
        linuxBase = base ++ [ ./home/linux.nix ];
        # mac ワークステーション (フル装備: バックアップ/マウント/メンテ/音楽)
        macWorkstation =
          base
          ++ [
            ./home/darwin.nix
            ./home/restic-backup.nix
            ./home/rclone-mount.nix
            ./home/maintenance.nix
          ]
          ++ secrets
          ++ [ ./home/mopidy.nix ]
          ++ station;
        # ヘッドレス AI ワーカー (sops なし)
        macminiHeadless = base ++ [ ./home/macmini.nix ];
        wsl = linuxBase ++ [ ./home/wsl.nix ] ++ secrets ++ station;
        linuxServer = linuxBase ++ secrets ++ station;
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
        # git-hooks の内部 pkgs は overlay 非適用のため、pre-commit 本体は
        # overlaid 版 (checkPhase 無効) を明示的に渡して CI の isatty テスト破損を回避。
        package = pkgs.pre-commit;
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
            # packages/checks/apps の評価でも standalone HM と同じ限定的な
            # unfree policy を使う。nix-fast-build は全systemを列挙するため、
            # legacyPackagesを直接使うとLinuxのunity-cliだけ評価に失敗する。
            systemPkgs = if isDarwinWorkstation then pkgs else mkPkgs system;
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
            }
            // lib.optionalAttrs (system == "x86_64-linux") {
              recovery-iso = inputs.self.nixosConfigurations."recovery-iso".config.system.build.isoImage;
            };
            apps = {
              check-all = {
                type = "app";
                meta.description = "Evaluate and build every check for the current system";
                program = lib.getExe (
                  systemPkgs.writeShellApplication {
                    name = "dotfiles-check-all";
                    runtimeInputs = [ systemPkgs.nix-fast-build ];
                    text = ''
                      flake_ref="''${DOTFILES_FLAKE:-./nix}"
                      if [[ -f flake.nix ]]; then
                        flake_ref=.
                      fi
                      exec nix-fast-build \
                        --flake "$flake_ref#checks" \
                        --systems ${system} \
                        --no-link \
                        "$@"
                    '';
                  }
                );
              };
              build-all = {
                type = "app";
                meta.description = "Build every package for the current system";
                program = lib.getExe (
                  systemPkgs.writeShellApplication {
                    name = "dotfiles-build-all";
                    runtimeInputs = [ systemPkgs.nix-fast-build ];
                    text = ''
                      flake_ref="''${DOTFILES_FLAKE:-./nix}"
                      if [[ -f flake.nix ]]; then
                        flake_ref=.
                      fi
                      exec nix-fast-build \
                        --flake "$flake_ref#packages" \
                        --systems ${system} \
                        --no-link \
                        "$@"
                    '';
                  }
                );
              };
            };
          }
          // lib.optionalAttrs isDarwinWorkstation {
            checks = {
              pre-commit = preCommit;
              config-invariants = import ./tests/config-invariants.nix {
                inherit
                  lib
                  user
                  ;
                pkgs = systemPkgs;
                inherit (inputs) self;
              };
            };
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
                systemPkgs.python3 # scripts/gen-docs.py (doc 生成ブロック)
                systemPkgs.bun
                systemPkgs.check-jsonschema
                systemPkgs.actionlint
              ];
            };
          }
          // lib.optionalAttrs (system == "x86_64-linux") {
            checks = {
              nixos-smoke = import ./tests/nixos-smoke.nix {
                inherit
                  home-manager
                  lanzaboote
                  user
                  ;
                pkgs = systemPkgs;
                inherit commonSpecialArgs;
              };
              preservation-smoke = import ./tests/preservation-smoke.nix {
                inherit preservation user;
                pkgs = systemPkgs;
              };
            };
          };
      };
    in
    perSystemOutputs
    // {
      # システム設定: sudo darwin-rebuild switch --flake .#<username>
      darwinConfigurations.${user.username} = mkHost.darwin {
        host = ./hosts/darwin.nix;
        specialArgs = {
          inherit user;
          brewNix = brew-nix;
        };
      };

      # ヘッドレス LLM ワーカー (M4 Mac mini / 24GB):
      #   sudo darwin-rebuild switch --flake .#macmini
      # workstation と同じ common.nix を共有しつつ GUI cask を積まない最小構成。
      # sops は積まない (age 鍵を macmini に持ち込まない方針)。
      darwinConfigurations.macmini = mkHost.darwin {
        host = ./hosts/macmini.nix;
        homeModules = roles.macminiHeadless;
      };

      # Android (Termux): nix-on-droid switch --flake .#default
      # 端末系 component (git/cli/shell/terminal) だけを積む軽量構成 (hosts/droid.nix)。
      nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
        pkgs = import nixpkgs { system = "aarch64-linux"; };
        modules = [ ./hosts/droid.nix ];
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

          # 起動不能・SSD交換時に、この repo を取得して disko / nixos-install を
          # 実行するための最小復旧 ISO。実機の Windows/ESP には自動で触れない。
          recovery-iso = nixpkgs-nixos.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit user; };
            modules = [
              "${nixpkgs-nixos}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./hosts/recovery-iso.nix
            ];
          };
        };

      # disko CLI 用 (ハード設定ファイル不要・guard 外)。インストール時に
      #   sudo disko --mode destroy,format,mount --flake <repo>/nix#nixos-laptop
      # で LUKS root パーティションだけを宣言的にフォーマット/マウントする。
      diskoConfigurations.nixos-laptop = import ./hosts/nixos-laptop-disk.nix;

      # macOS ユーザー設定: home-manager switch --flake .#<username>
      homeConfigurations.${user.username} = mkHost.home { modules = roles.macWorkstation; };

      # WSL2 ユーザー設定: home-manager switch --flake .#<username>-wsl
      # Lab PC 等の Windows + WSL2 環境で使う
      homeConfigurations."${user.username}-wsl" = mkHost.home {
        targetSystem = "x86_64-linux";
        wsl = true;
        modules = roles.wsl;
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
          osUser = builtins.getEnv "USER";
          labUser = user // (if osUser != "" then { username = osUser; } else { });
        in
        mkHost.home {
          targetSystem = "x86_64-linux";
          wsl = true;
          modules = roles.wsl;
          specialArgs = {
            user = labUser;
            nixIndexDatabase = nix-index-database;
            agentSkills = agent-skills;
          };
        };

      # Linux サーバー / 自宅 NUC / VPS 用: .#<username>-linux
      # 純 Linux (WSL interop なし)。aarch64 / x86_64 両対応
      homeConfigurations."${user.username}-linux" = mkHost.home {
        targetSystem = "x86_64-linux";
        modules = roles.linuxServer;
      };
      homeConfigurations."${user.username}-linux-aarch64" = mkHost.home {
        targetSystem = "aarch64-linux";
        modules = roles.linuxServer;
      };
    };
}
