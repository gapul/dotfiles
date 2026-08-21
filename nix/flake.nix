{
  description = "macOS dotfiles managed with Nix flakes (nix-darwin + home-manager + sops-nix)";

  # NOTE: Caches (cache.nixos.org / nix-community / flakehub) are declared not in the flake's nixConfig
  # but in the system's /etc/nix/nix.custom.conf (postActivation in hosts/darwin.nix).
  # flake nixConfig prints "Using saved setting..." on every nh run and pushes toward trusting arbitrary
  # flake settings, so the policy is to keep it on the system side with least privilege.

  inputs = {
    # Align on the 26.05 series (avoids the nix-darwin#1462 'USER is root' regression)
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    # For zrythm-darwin (nix/pkgs/zrythm-darwin) only. On 26.05-darwin, appstream-1.1.2 can't
    # build on darwin (via a libadwaita dependency), so build just that one package with unstable
    # pkgs. Don't add follows (keep it as a separate lineage that doesn't drag in other inputs).
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # herdr only. nixpkgs-unstable is held at a revision where the darwin creative apps still
    # build (ardour / aseprite / fritzing), so it cannot be moved just to pick up a herdr
    # release: as of 2026-08 aseprite 1.3.18.1 fails on aarch64-darwin with
    # "no member named 'format' in namespace 'fmt'" (NixOS/nixpkgs#552132, still open).
    # Give herdr its own lineage instead, the same way nixpkgs-nixos is separate.
    nixpkgs-herdr.url = "github:NixOS/nixpkgs/nixos-unstable";

    # For the real NixOS machine (Windows dual-boot HP laptop, x86_64).
    # Separated from the darwin channels to hit the nixos cache cleanly.
    nixpkgs-nixos.url = "github:NixOS/nixpkgs/nixos-26.05";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS inside Windows (WSL2). Shares roles.wsl with the Lab PC's standalone home,
    # so the shell and CLI are identical whichever way the machine is booted.
    # Tracks the nixos lineage, not the darwin one (this host is x86_64-linux).
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-nixos";
    };

    # Nix environment on Android (Termux). The release branch is stuck at 24.05, so
    # use master with nixpkgs follows (the usual nix-on-droid approach). aarch64-linux.
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/master";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # The Mopidy build-time patch set is split into a separate repo (trims 336 files from dotfiles).
    # Pulled in as a flake=false source and passed to patchDir in nix/lib/mopidy-env.nix.
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

    # NixOS Secure Boot support (signed UKI). Used only on nixos-laptop.
    lanzaboote.url = "github:nix-community/lanzaboote/v1.1.0";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs-nixos";

    # disko: declarative disk layout. Manages only nixos-laptop's LUKS root (for dual-boot safety).
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-nixos";

    # NixOS module that makes persistence targets explicit. Try it in a VM smoke test only for now;
    # don't apply it to the real machine until the data migration procedure is settled.
    preservation.url = "github:nix-community/preservation";

    # Code quality: pre-commit hook declaration + treefmt (nix fmt)
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Modularize flake outputs incrementally. Migrate the per-system outputs first.
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    # Trial introduction of treating Homebrew casks as Nix derivations. brew-api updates its freshness separately.
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
    brew-nix.url = "github:BatteredBunny/brew-nix";
    brew-nix.inputs.brew-api.follows = "brew-api";
    brew-nix.inputs.nixpkgs.follows = "nixpkgs";
    brew-nix.inputs.nix-darwin.follows = "nix-darwin";

    # Declaratively own the Homebrew installation itself (not just the package list).
    # nix-darwin's homebrew module assumes brew is already installed by hand; this makes the
    # prefix a nix-managed thing, so a fresh mac needs no curl-into-bash bootstrap step.
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # The ACP adapter that lets Hermes run inference on the Claude subscription. It used to live in
    # configs/macmini/, but it is a part of Hermes' plumbing rather than a machine setting, so it
    # has its own repo now. This flake only says which machine installs it.
    claude-acp.url = "github:gapul/claude-acp";
    claude-acp.inputs.nixpkgs.follows = "nixpkgs";

    # Secure Enclave SSH identities as a CLI + nix-darwin module, replacing the Secretive cask.
    # Same hardware guarantee (the private key never leaves the enclave) without a GUI app or a
    # resident agent process: it hands the identity to macOS' own CryptoTokenKit provider.
    nix-secure-enclave-key.url = "github:ryoppippi/nix-secure-enclave-key";
    nix-secure-enclave-key.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      claude-acp,
      nix-secure-enclave-key,
      nixpkgs,
      nixpkgs-nixos,
      nixpkgs-unstable,
      nixpkgs-herdr,
      nix-darwin,
      home-manager,
      nix-on-droid,
      nixos-wsl,
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
      nix-homebrew,
      ...
    }:
    let
      system = "aarch64-darwin";

      # Overlay that absorbs temporary breakage in upstream nixpkgs (SSO: lib/overlays.nix).
      # The nix-darwin system's hosts/darwin-common.nix imports the same one
      # (unless applied to both, the pre-commit of the home embedded in the darwin system stays vanilla).
      overlayFixes = import ./lib/overlays.nix;

      # Selectively allow only the official proprietary CLIs used by standalone Home Manager.
      # This is a separate instance from the nix-darwin side's pkgs config, so it's needed here too.
      mkPkgs =
        targetSystem:
        import nixpkgs {
          system = targetSystem;
          config.allowUnfreePredicate =
            pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "unity-cli"
              "vroid-studio" # free of charge but proprietary, see pkgs/vroid-studio.nix
            ];
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
        nixpkgsUnstable = nixpkgs-unstable;
        nixpkgsHerdr = nixpkgs-herdr;
        secureEnclaveKey = nix-secure-enclave-key;
      };

      # ECS "System" = host composer (unifies the darwin / home boilerplate)
      mkHost = import ./lib/mk-host.nix {
        inherit
          nixpkgs
          nix-darwin
          home-manager
          nix-homebrew
          user
          system
          commonSpecialArgs
          mkPkgs
          mkWslPkgs
          ;
      };

      # ECS "role" = a bundle of components (home/*.nix). A host just combines roles.
      # The ordering affects list concatenation order for home.packages etc., so keep it identical to the existing config.
      roles = rec {
        base = [ ./home/common.nix ];
        secrets = [
          sops-nix.homeManagerModules.sops
          ./home/secrets.nix
        ];
        station = [ ./home/workstation.nix ];
        linuxBase = base ++ [ ./home/linux.nix ];
        # mac workstation (fully equipped: backup/mount/maintenance/music)
        macWorkstation =
          base
          ++ [
            ./home/darwin.nix
            ./home/restic-backup.nix
            ./home/rclone-mount.nix
            ./home/mutagen-sync.nix
            ./home/personal-history.nix # 個人の記録を端末ごとに書き出して Syncthing に載せる
            ./home/maintenance.nix
            ./home/git-hooks.nix # git hook that auto-rebuilds on main updates (main tree only)
          ]
          ++ secrets
          ++ [
            ./home/secrets-darwin.nix # mac-only secrets (secrets/darwin.yaml)
            ./home/mopidy.nix
          ]
          ++ station;
        # headless AI worker (no sops). The backup module is separate from the
        # workstation's because it reads its password and ntfy credentials from
        # hand-placed files rather than sops, and leaves pruning to the workstation.
        macminiHeadless = base ++ [
          ./home/macmini.nix
          ./home/macmini-backup.nix
        ];
        wsl = linuxBase ++ [ ./home/wsl.nix ] ++ secrets ++ station;
        linuxServer = linuxBase ++ secrets ++ station;
      };

      # Home server (x86_64, replacing the single-node Proxmox box outright).
      # Unlike nixos-laptop there is no uncommitted hardware-configuration.nix to wait
      # for: the box is dedicated, so disko owns the whole disk and generates
      # fileSystems, and hosts/homeserver-hardware.nix holds the rest by hand. CI
      # therefore builds exactly what gets installed, which is the only verification
      # available when the swap has no per-service rollback.
      homeserver = nixpkgs-nixos.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit user; };
        modules = [
          # Same SSO overlay as the other hosts (carries e.g. tailscale's vendorHash fix).
          { nixpkgs.overlays = [ overlayFixes ]; }
          ./hosts/homeserver.nix
          disko.nixosModules.disko
          ./hosts/homeserver-disk.nix
        ];
      };

      # Tool set to run from rootless Nix (nix-portable) on an SSH target.
      # Supports both Linux x86_64 / aarch64.
      remoteTools =
        pkgs': with pkgs'; [
          # zsh 一式。母艦と同じ体験 (ゴーストテキスト補完 / 構文ハイライト /
          # fzf-tab) をリモートでも出すため。設定は configs/shell/zshrc.remote が
          # store から直接読む (home-manager はリモートで動かせないため)。
          zsh
          zsh-autosuggestions
          zsh-syntax-highlighting
          zsh-fzf-tab
          zsh-history-substring-search
          starship
          neovim
          yazi
          tmux
          # herdr は母艦と同じ nixpkgs-herdr から取る (stable の 26.05 系でも
          # nixpkgs-unstable でもなく)。`herdr --remote` は両端が同じビルドでないと
          # attach を拒否し、版が合わないとクライアントが自前のコピーを ~/.local/bin に
          # 落とす。remote-env に入れておけば flake の pin が両端を揃えるので、その
          # フォールバックが発火しない (modules/home/packages.nix の herdrPkgs.herdr と対)。
          nixpkgs-herdr.legacyPackages.${pkgs'.stdenv.hostPlatform.system}.herdr
          git
          lazygit
          ripgrep
          fd
          fzf
          bat
          eza
          zoxide
          curl
          wget
        ];
      # nix fmt: bundles nixfmt(nix) + shfmt(shell)
      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.shfmt.enable = true;
        settings.formatter.shfmt.options = [
          "-i"
          "2"
        ]; # 2-space (per CLAUDE.md)
      };

      # Declare pre-commit hooks in nix. src is nix/ (flake subtree).
      # The whole repo (scripts/ etc.) is covered by running `pre-commit run --all-files` at the git root.
      preCommit = git-hooks.lib.${system}.run {
        src = ./.;
        # git-hooks' internal pkgs is unoverlaid, so pass the overlaid pre-commit itself
        # (checkPhase disabled) explicitly to avoid the CI isatty test breakage.
        package = pkgs.pre-commit;
        hooks = {
          # Formatting uses per-file nixfmt (since the flake is in nix/, the treefmt hook
          # fails root detection from the git root. treefmt is dedicated to nix fmt).
          nixfmt.enable = true;
          # statix is excluded from enforced hooks: repeated_keys etc. clash with module notation,
          # and the --config path can't be made unique across flake/git-root.
          # Manual checks are possible with `nix run nixpkgs#statix -- check nix`.
          deadnix = {
            enable = true; # unused nix code
            settings.noLambdaPatternNames = true; # allow unused args like { lib, ... }
          };
          shellcheck = {
            enable = true; # shell script lint (follows .shellcheckrc)
            # .shellcheckrc に severity=error と書いてあるが、あれは効いていない。
            # shellcheck 0.11 の rc が解釈するのは disable= の類だけで、severity は
            # CLI 専用 (実測: 同じ rc に置いた disable=SC2001 は効き、severity=error は
            # 無視されて style の指摘がそのまま出て exit 1 になる)。つまり「gate は
            # error 級のみ」という意図は最初から実現していなかった。ここで渡し直す。
            args = [ "--severity=error" ];
            excludes = [
              # The sketchybar configs stylistically use a lot of intentional word splitting, handled separately
              # (manual check: nix develop ./nix -c shellcheck configs/wm/sketchybar/...)
              "configs/wm/sketchybar/.*"
              # direnv files have no shebang and assume the direnv stdlib
              "\\.envrc$"
              # zsh は shellcheck の対象外 (SC1071)。拡張子で外すのは、下の macmini の
              # ように後からディレクトリを足していく形だと取りこぼすため。実際
              # configs/shell/*.zsh が漏れていて、`just fmt` は origin/main でも
              # SC1072 で落ちていた。prompt.zsh の `f() { x=$y }` も evalcache.zsh の
              # `${${x}}` も zsh としては正しく、shellcheck が読めないだけなので、
              # 書き換えて黙らせるのは筋が悪い。
              "\\.zsh$"
              # 拡張子を持たない zsh もある。macmini の AI コマンドは shebang だけが zsh
              "configs/macmini/bin/.*"
              # Same for their 母艦-side client wrappers
              "configs/macmini/client/.*"
              # Archive of one-shot scripts from macmini setup (historical artifacts, not style-refactored)
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
            # Use the same limited unfree policy as standalone HM when evaluating
            # packages/checks/apps too. nix-fast-build enumerates all systems, so using
            # legacyPackages directly makes only Linux's unity-cli fail evaluation.
            systemPkgs = if isDarwinWorkstation then pkgs else mkPkgs system;
          in
          {
            formatter = if isDarwinWorkstation then treefmtEval.config.build.wrapper else systemPkgs.nixfmt;
            packages = {
              unity-cli = systemPkgs.callPackage ./pkgs/unity-cli.nix { };

              # iOS の構成プロファイル。中身は生成した XML だけなのでどの system でも建つ。
              # 端末への配布は mobile/ios/profiles/serve.sh がこの出力を読む。
              ios-profiles = import ./mobile/ios-profiles.nix {
                inherit lib user;
                pkgs = systemPkgs;
              };

              # What a pull request has to prove: the machines in daily use still evaluate and
              # build. Everything else this flake produces — the macmini closure, the NixOS
              # hosts, the VM tests — is built on main, which is also where cachix gets filled.
              # omnix builds every output of a subflake and has no selector, so the subset has
              # to be expressed as an output of its own and built directly.
              pr-gate = systemPkgs.linkFarmFromDrvs "pr-gate" (
                lib.optionals isDarwinWorkstation [
                  inputs.self.darwinConfigurations.${user.username}.system
                  inputs.self.homeConfigurations.${user.username}.activationPackage
                  # Formatting and the other hooks, on the PR rather than after the merge.
                  # It is seconds of work and it is the only check that has ever gone red on
                  # main while the pull request that caused it was green — nixfmt disagreeing
                  # about how to fold an expression is not something to find out later.
                  inputs.self.checks.${system}.pre-commit
                ]
                ++ lib.optionals (system == "x86_64-linux") [
                  inputs.self.homeConfigurations."${user.username}-wsl".activationPackage
                  inputs.self.homeConfigurations."labpc-wsl".activationPackage
                  inputs.self.homeConfigurations."${user.username}-linux".activationPackage
                ]
                ++ lib.optionals (system == "aarch64-linux") [
                  inputs.self.homeConfigurations."${user.username}-linux-aarch64".activationPackage
                ]
              );
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
            }
            // lib.optionalAttrs (system == "aarch64-linux") {
              # nix-on-droid is outside omnix's standard build targets and requires --impure
              # via builtins.storePath, so make it a dedicated app called from om ci's custom step.
              ci-nixondroid = {
                type = "app";
                meta.description = "Build the nix-on-droid activation package (impure)";
                program = lib.getExe (
                  systemPkgs.writeShellApplication {
                    name = "ci-nixondroid";
                    runtimeInputs = [
                      systemPkgs.nix
                      systemPkgs.git
                    ];
                    text = ''
                      flake_ref="''${DOTFILES_FLAKE:-./nix}"
                      if [[ -f flake.nix ]]; then
                        flake_ref=.
                      fi
                      # Prebuilds like proot-termux are only available from the official cachix.
                      # Don't rewrite nix.conf with sudo; assume a trusted user and pass CLI flags.
                      exec nix build --impure \
                        --extra-substituters https://nix-on-droid.cachix.org \
                        --extra-trusted-public-keys nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU= \
                        "$flake_ref#nixOnDroidConfigurations.default.activationPackage" \
                        --no-link --show-trace "$@"
                    '';
                  }
                );
              };
            };

            # So that omnix (om ci) can pick up standalone home-manager configs,
            # expose the top-level homeConfigurations under legacyPackages as an alias.
            # omnix detects and builds the activationPackage of legacyPackages.<system>.homeConfigurations.*
            # (since top-level homeConfigurations are not targeted).
            legacyPackages =
              lib.optionalAttrs (system == "x86_64-linux") {
                homeConfigurations = {
                  "${user.username}-wsl" = inputs.self.homeConfigurations."${user.username}-wsl";
                  "labpc-wsl" = inputs.self.homeConfigurations."labpc-wsl";
                  "${user.username}-linux" = inputs.self.homeConfigurations."${user.username}-linux";
                };
              }
              // lib.optionalAttrs (system == "aarch64-linux") {
                homeConfigurations."${user.username}-linux-aarch64" =
                  inputs.self.homeConfigurations."${user.username}-linux-aarch64";
              }
              // lib.optionalAttrs isDarwinWorkstation {
                homeConfigurations."${user.username}" = inputs.self.homeConfigurations."${user.username}";
              };

            # Available on every system, because om ci runs the lint / gitleaks / generated-drift
            # steps inside it and those belong on a job with slack rather than on the darwin one
            # that also fetches every system closure.
            # preCommit is bound to `system` from the outer let (aarch64-darwin), so its packages
            # are Mach-O binaries. Putting them in a Linux shell got them execve'd, xargs fell back
            # to /bin/sh, and dash reported a syntax error inside the ELF. They stay darwin-only;
            # the git hooks are a local-dev convenience and checks.pre-commit is darwin-only too.
            devShells.default = systemPkgs.mkShell (
              {
                buildInputs = [
                  systemPkgs.shellcheck
                  systemPkgs.statix
                  systemPkgs.stylua
                  systemPkgs.taplo
                  systemPkgs.yq-go
                  systemPkgs.jq
                  systemPkgs.just
                  systemPkgs.python3 # scripts/gen-docs.py (doc generation block)
                  systemPkgs.bun
                  systemPkgs.check-jsonschema
                  systemPkgs.actionlint
                  systemPkgs.gitleaks # om ci's gitleaks custom step
                  systemPkgs.git # ci-lint / ci-gitleaks use git ls-files / rev-parse
                ]
                ++ lib.optionals isDarwinWorkstation preCommit.enabledPackages;
              }
              // lib.optionalAttrs isDarwinWorkstation { inherit (preCommit) shellHook; }
            );
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
              evalcache = import ./tests/evalcache.nix { pkgs = systemPkgs; };
              prompt = import ./tests/prompt.nix { pkgs = systemPkgs; };
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
              # The home server replaces Proxmox in one cut, so this booting is the
              # only verification before the old install is gone.
              homeserver-vm = import ./tests/homeserver-vm.nix {
                inherit user;
                pkgs = systemPkgs;
              };
            };
          };
      };
    in
    perSystemOutputs
    // {
      # System config: sudo darwin-rebuild switch --flake .#<username>
      darwinConfigurations.${user.username} = mkHost.darwin {
        host = ./hosts/darwin.nix;
        specialArgs = {
          inherit user;
          brewNix = brew-nix;
          # hosts/darwin.nix declares the .app-shipping creative tools, which come from
          # nixos-unstable (see lib/unstable-pkgs.nix).
          nixpkgsUnstable = nixpkgs-unstable;
        };
      };

      # Headless LLM worker (M4 Mac mini / 24GB):
      #   sudo darwin-rebuild switch --flake .#macmini
      # A minimal config that shares the same common.nix as the workstation but adds no GUI casks.
      # No sops (policy of not bringing the age key onto the macmini).
      darwinConfigurations.macmini = mkHost.darwin {
        host = ./hosts/macmini.nix;
        homeModules = roles.macminiHeadless;
        specialArgs = {
          inherit user;
          claudeAcp = claude-acp.packages.${system}.default;
        };
      };

      # Android (Termux): nix-on-droid switch --flake .#default
      # A lightweight config loading only terminal-oriented components (git/cli/shell/terminal) (hosts/droid.nix).
      nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
        pkgs = import nixpkgs { system = "aarch64-linux"; };
        modules = [ ./hosts/droid.nix ];
      };

      # Real NixOS machine (Windows dual-boot): sudo nixos-rebuild switch --flake .#nixos-laptop
      # Integrate home-manager as a NixOS module and share the same
      # home/common.nix + home/linux.nix as macOS / WSL for the user config.
      #
      # hosts/nixos-laptop-hardware.nix is the machine-specific file emitted by `nixos-generate-config`
      # on the real machine. Until it exists, don't grow the output at all, so that
      # `nix flake check` / pre-commit on the Mac don't fail on an import error.
      nixosConfigurations =
        nixpkgs-nixos.lib.optionalAttrs (builtins.pathExists ./hosts/nixos-laptop-hardware.nix) {
          "nixos-laptop" = nixpkgs-nixos.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit user; };
            modules = [
              # SSO overlay absorbing upstream nixpkgs breakage (shared with darwin/standalone home).
              # Override things like tailscale's wrong vendorHash here.
              { nixpkgs.overlays = [ overlayFixes ]; }
              ./hosts/nixos-laptop.nix
              lanzaboote.nixosModules.lanzaboote
              disko.nixosModules.disko
              ./hosts/nixos-laptop-disk.nix
              # Leave runtime fileSystems/luks to the generated hardware-configuration.nix, and
              # use disko only as an "install-time format/mount tool".
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
                    ./home/hyprland.nix # Hyprland rice (nixos-laptop only)
                    ./home/ssh-tpm-agent.nix # TPM-sealed SSH key (nixos-laptop only: WSL has no TPM)
                    ./home/dev.nix # dev environment such as direnv
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
          # Home server: sudo nixos-rebuild switch --flake .#homeserver
          # No pathExists guard, unlike nixos-laptop: nothing about this host is
          # uncommitted, so it is always evaluable and CI always builds it.
          inherit homeserver;

          # Config for CI-evaluating the common NixOS settings without exposing the machine-specific hardware-configuration.
          "nixos-laptop-ci" = nixpkgs-nixos.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {
              inherit user;
              hardwareConfig = ./hosts/nixos-laptop-hardware-ci.nix;
            };
            modules = [
              # SSO overlay absorbing upstream nixpkgs breakage (shared with darwin/standalone home).
              # Override things like tailscale's wrong vendorHash here.
              { nixpkgs.overlays = [ overlayFixes ]; }
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
                  ./home/ssh-tpm-agent.nix
                  ./home/workstation.nix
                ];
              }
            ];
          };

          # Windows の中の NixOS (WSL2)。tarball を作って wsl --import で入れる:
          #   sudo nix run <flake>#nixosConfigurations.wsl.config.system.build.tarballBuilder
          # 実機のデュアルブート NixOS とはインストールを共有しない (WSL2 は物理
          # パーティションを起動できない)。共有するのは home の roles.wsl のほう。
          "wsl" = nixpkgs-nixos.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit user; };
            modules = [
              { nixpkgs.overlays = [ overlayFixes ]; }
              nixos-wsl.nixosModules.default
              ./hosts/wsl.nix
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.backupFileExtension = "hm-bak";
                home-manager.extraSpecialArgs = commonSpecialArgs;
                home-manager.users.${user.username}.imports = roles.wsl;
              }
            ];
          };

          # Minimal recovery ISO for fetching this repo and running disko / nixos-install
          # when unbootable or replacing the SSD. Does not automatically touch the machine's Windows/ESP.
          recovery-iso = nixpkgs-nixos.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit user; };
            modules = [
              "${nixpkgs-nixos}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./hosts/recovery-iso.nix
            ];
          };
        };

      # For the disko CLI (no hardware config file needed, outside the guard). At install time,
      #   sudo disko --mode destroy,format,mount --flake <repo>/nix#nixos-laptop
      # declaratively formats/mounts only the LUKS root partition.
      diskoConfigurations.nixos-laptop = import ./hosts/nixos-laptop-disk.nix;

      # Home server: disko owns the whole NVMe (no dual boot to protect), so this
      # both formats at install time and provides the runtime fileSystems.
      #   sudo disko --mode destroy,format,mount --flake <repo>/nix#homeserver
      diskoConfigurations.homeserver = import ./hosts/homeserver-disk.nix;

      # macOS user config: home-manager switch --flake .#<username>
      homeConfigurations.${user.username} = mkHost.home { modules = roles.macWorkstation; };

      # WSL2 user config: home-manager switch --flake .#<username>-wsl
      # Used on Windows + WSL2 environments such as the Lab PC
      homeConfigurations."${user.username}-wsl" = mkHost.home {
        targetSystem = "x86_64-linux";
        wsl = true;
        modules = roles.wsl;
      };

      # For the Lab PC (a WSL2 environment whose OS username differs from the Mac's username):
      # to avoid leaving personal info in the public repo, take the username from $USER at runtime.
      # .gitignore'd files aren't included in the flake source, so the user.local.nix pattern
      # doesn't work; handle it with builtins.getEnv "USER" + the --impure flag.
      #
      # Usage:
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
          # Only the username differs from every other home config, so start from
          # commonSpecialArgs instead of re-listing its members (re-listing meant this host
          # silently missed any arg added later, e.g. nixpkgsUnstable).
          specialArgs = commonSpecialArgs // {
            user = labUser;
          };
        };

      # For Linux servers / home NUC / VPS: .#<username>-linux
      # Pure Linux (no WSL interop). Supports both aarch64 / x86_64
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
