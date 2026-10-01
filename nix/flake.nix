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

    # Fast-moving agent/developer CLIs (Codex / OpenCode / Claude / Atuin / security tools / herdr).
    # nixpkgs-unstable is held at a revision where the darwin creative apps still build
    # (ardour / aseprite / fritzing), so it cannot be moved just to pick up these releases:
    # as of 2026-08 aseprite 1.3.18.1 fails on aarch64-darwin with
    # "no member named 'format' in namespace 'fmt'" (NixOS/nixpkgs#552132, still open).
    # Give agents their own rolling lineage instead, the same way nixpkgs-nixos is separate.
    nixpkgs-agents.url = "github:NixOS/nixpkgs/nixos-unstable";

    # For the real NixOS machines (homeserver, and the Windows dual-boot HP laptop).
    # Separated from the darwin channels to hit the nixos cache cleanly.
    #
    # Tracks the rolling branch (switched from nixos-26.05 on 2026-08-31). The stable branch was
    # doing real damage in this setup: searxng sat 3.5 months stale and search broke entirely,
    # and tailscale was 4 releases behind upstream. Each time we escaped to nixpkgsUnstable
    # individually, and the more exceptions piled up, the harder it was to tell what was current.
    #
    # The nixpkgs stable branch is not like Debian stable. Fixes land in unstable first, and the
    # more niche a package, the less likely it is to be backported. What runs here is the long
    # tail (searxng / mautrix / attic / dawarich), so stable tends to mean "a version pinned
    # even though upstream already fixed it".
    #
    # We can afford this because breakage is noticed and rolled back: changes reach main only
    # after CI passes on 3 platforms, self-deploy pulls every hour, and on failure the old
    # generation stays and a notification goes out (#500). The "boots but is broken inside"
    # kind is caught by the restart-loop detector (#490).
    #
    # The darwin side stays on 26.05. It has the nix-darwin#1462 regression and
    # ardour/aseprite/fritzing failing to build on unstable (see the nixpkgs and
    # nixpkgs-unstable comments above). Those constraints are darwin-specific and don't apply here.
    nixpkgs-nixos.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # The NixOS hosts (laptop, WSL) run nixpkgs-nixos = nixos-unstable, so they need Home Manager's
    # master branch: release-26.05 against unstable warns about the version mismatch and trips
    # nixpkgs deprecations (`stdenv.isLinux`) inside its own modules.
    home-manager-nixos.url = "github:nix-community/home-manager";
    home-manager-nixos.inputs.nixpkgs.follows = "nixpkgs-nixos";

    # NixOS inside Windows (WSL2). Shares roles.wsl with the Lab PC's standalone home,
    # so the shell and CLI are identical whichever way the machine is booted.
    # Tracks the nixos lineage, not the darwin one (this host is x86_64-linux).
    #
    # main, not release-26.05: nixpkgs-nixos follows nixos-unstable, and the release
    # branch still sets `boot.bootspec.enable`, which unstable removed. The release
    # branch only makes sense against a matching release of nixpkgs, and evaluating
    # it against unstable fails the assertion on every build.
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
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

    # Formera's backend is built from current main so the local compatibility
    # patch can be dropped as soon as upstream fixes its malformed rate-limit
    # headers. The weekly lock update keeps this rolling with the other services.
    formera-source = {
      url = "github:FormeraApp/Formera";
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

    # Stylix: applies one palette to the things nix cannot reach by hand — GTK, Qt and the
    # launcher, which otherwise render in their stock white and look pasted onto the rice.
    # Used only on nixos-laptop, and with autoEnable off, so it themes what it is asked to
    # and leaves the hand-written configs (ghostty, yazi, bat …) alone. The palette still
    # comes from configs/theme/palettes.json, so that file stays the single source of truth.
    stylix.url = "github:nix-community/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs-nixos";

    # arkenfox user.js exposed as typed home-manager options (section / subsection / pref),
    # so the hardening lives in the flake lock and the overrides are visible as nix diffs.
    # Used by modules/home/firefox.nix (the Mac and the NixOS laptop).
    arkenfox.url = "github:HeitorAugustoLN/arkenfox-nix";
    arkenfox.inputs.nixpkgs.follows = "nixpkgs";

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

    # Compiler that builds Apple Shortcuts from code. We stopped hand-assembling plists after a
    # trap hit on 2026-09-27: iOS 26 built-in actions mix old and new parameter names, and the
    # old spelling (WFInput/WFDictionaryKey) is silently ignored, producing a shortcut whose
    # variables never get passed. cherri emits the same spelling as the device, so leave it to it.
    cherri.url = "github:electrikmilk/cherri";
    cherri.inputs.nixpkgs.follows = "nixpkgs";

    # Secure Enclave SSH identities as a CLI + nix-darwin module, replacing the Secretive cask.
    # Same hardware guarantee (the private key never leaves the enclave) without a GUI app or a
    # resident agent process: it hands the identity to macOS' own CryptoTokenKit provider.
    nix-secure-enclave-key.url = "github:ryoppippi/nix-secure-enclave-key";

    # Home-made tool for using mocopi (Sony's motion capture) on macOS. The source should stay
    # private, so it is fetched over git+ssh rather than github:. CI holds a read-only deploy key
    # via ssh-agent (.github/actions/setup-nix). Real machines use their usual GitHub auth.
    mocopi-mac.url = "git+ssh://git@github.com/gapul/mocopi-mac?ref=main";
    mocopi-mac.inputs.nixpkgs.follows = "nixpkgs";
    nix-secure-enclave-key.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      cherri,
      claude-acp,
      nix-secure-enclave-key,
      mocopi-mac,
      nixpkgs,
      nixpkgs-nixos,
      nixpkgs-unstable,
      nixpkgs-agents,
      nix-darwin,
      home-manager,
      home-manager-nixos,
      nix-on-droid,
      nixos-wsl,
      mopidy-patches,
      nix-index-database,
      agent-skills,
      sops-nix,
      lanzaboote,
      disko,
      stylix,
      preservation,
      git-hooks,
      treefmt-nix,
      flake-parts,
      brew-nix,
      nix-homebrew,
      formera-source,
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
            ]
            # voicevox-engine and its core/onnxruntime/resource parts, for the
            # ~/.local/bin/voicevox-engine wrapper in home/darwin.nix. The voice models are
            # what makes them unfree; the system layer already allows them wholesale.
            || nixpkgs.lib.hasPrefix "voicevox" (nixpkgs.lib.getName pkg);
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
        nixpkgsAgents = nixpkgs-agents;
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

      darwinWorkstationSpecialArgs = {
        inherit user;
        brewNix = brew-nix;
        mocopiMac = mocopi-mac;
        nixpkgsAgents = nixpkgs-agents;
        inherit cherri;
        # Offload heavy builds to the macmini. It is the same aarch64-darwin, so they run as is.
        #
        # The nix daemon sshes as root, so the key location is explicit. root reads files
        # regardless of permissions, so point at the everyday automation key directly
        # (a root-only key would just be one more secret to manage).
        #
        # 10 is the macmini's core count, 1 the speed factor. big-parallel marks "send
        # parallel-friendly derivations here"; heavy things like Chromium and LLVM qualify.
        #
        # Without builders-use-substitutes, the macmini's dependencies get transferred from the
        # main Mac, losing the benefit of pulling them straight from the cache.
        nixCustomConf = {
          # Written as the tailnet IP, not the hostname. The nix daemon runs as root, so it
          # doesn't read ~/.ssh/config and can't resolve "macmini"
          # (Could not resolve hostname macmini).
          #
          # root's ~/.ssh/known_hosts needs the macmini host key. Without it the build stops
          # with "Host key verification failed". This is a one-time manual step:
          #   sudo sh -c 'ssh-keyscan -H 100.105.135.49 >> /var/root/.ssh/known_hosts'
          builders = "ssh-ng://gapul@100.105.135.49 aarch64-darwin /Users/gapul/.ssh/id_automation 10 1 big-parallel,benchmark";
          builders-use-substitutes = "true";
        };
        # hosts/darwin.nix declares the .app-shipping creative tools, which come from
        # nixos-unstable (see lib/unstable-pkgs.nix).
        nixpkgsUnstable = nixpkgs-unstable;
      };
      darwinWorkstation =
        includeManualSources:
        mkHost.darwin {
          host = ./hosts/darwin.nix;
          specialArgs = darwinWorkstationSpecialArgs // {
            inherit includeManualSources;
          };
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
            # programs.firefox.arkenfox options for modules/home/firefox.nix (imported via
            # modules/home/darwin-firefox.nix from home/darwin.nix). A flake input module has to enter through the role list.
            inputs.arkenfox.modules.homeManager.arkenfox
            ./home/restic-backup.nix
            ./home/rclone-mount.nix
            ./home/personal-history.nix # export personal records per machine and put them on Syncthing
            ./home/maintenance.nix
            ./home/tmp-cleanup.nix # auto-clean ~/tmp scratch after 7 days (shared with macminiHeadless)
            ./home/nix-gc-tcc.nix # stable copy of signed nix used by the root GC daemon (hosts/darwin-common.nix)
            ./home/git-hooks.nix # git hook that auto-rebuilds on main updates (main tree only)
            ./home/mail-app.nix # keep Mail.app running in the background so native verification-code AutoFill works
          ]
          ++ secrets
          ++ [
            ./home/secrets-darwin.nix # mac-only secrets (secrets/darwin.yaml)
            ./home/matrix-cli.nix # matrix-send/read/rooms for agents (bot token from secrets/common.yaml)
            ./home/mopidy.nix
          ]
          ++ station;
        # headless AI worker. No home-manager sops: the secrets it needs are placed by the
        # system-side sops in hosts/macmini.nix (host-key decryption, which home-manager cannot do).
        # The backup module is separate from the workstation's because it reads the plain default
        # paths rather than sops.secrets attributes.  It also owns repository-wide
        # prune/check/monitor as the always-on backup control plane.
        macminiHeadless = base ++ [
          ./home/macmini.nix
          ./home/macmini-maintenance.nix
          ./home/macmini-backup.nix
          ./home/macmini-watchdog.nix
          ./home/findmy-tag.nix # periodic Find My tag fetch; lives on this always-on machine, not the laptop
          # iMessage bridge. The other mautrix bridges live on homeserver, but this one needs
          # chat.db and Messages.app, so it can only run on this machine.
          ./home/macmini-imessage.nix
          # Heavy rendering, so it doesn't tie up the main Mac.
          ./home/macmini-render.nix
          # Voice models and synthesis. Clients use the API over the tailnet.
          ./home/macmini-aivisspeech.nix
          ./home/tmp-cleanup.nix # auto-clean ~/tmp scratch after 7 days (shared with macWorkstation)
          ./home/nix-gc-tcc.nix # stable copy of signed nix used by the root GC daemon (hosts/darwin-common.nix)
          # dotfiles-pull (home/macmini.nix) relies on the post-merge hook to rebuild, but this role
          # had no module installing the hook, so .git/hooks still held an old copy placed by hand on
          # 2026-08-09 (it didn't rebuild on secrets/ changes). Declare it so activation updates it.
          ./home/git-hooks.nix
        ];
        wsl = linuxBase ++ [ ./home/wsl.nix ] ++ secrets ++ station;
        linuxServer = linuxBase ++ secrets ++ station;
        # Shared hosts where the age key must never exist (other people hold sudo), e.g. the
        # company GPU box reached through rootless docker. No secrets, no desktop extras.
        linuxShared = linuxBase;
      };

      # Home server (x86_64, replacing the single-node Proxmox box outright).
      # Unlike nixos-laptop there is no uncommitted hardware-configuration.nix to wait
      # for: the box is dedicated, so disko owns the whole disk and generates
      # fileSystems, and hosts/homeserver-hardware.nix holds the rest by hand. CI
      # therefore builds exactly what gets installed, which is the only verification
      # available when the swap has no per-service rollback.
      homeserver = nixpkgs-nixos.lib.nixosSystem {
        system = "x86_64-linux";
        # nixpkgs-nixos itself now tracks nixos-unstable, so no per-package escapes are needed
        # (2026-08-31). searxng and tailscale both get their latest from this input.
        specialArgs = { inherit user formera-source; };
        modules = [
          # Same SSO overlay as the other hosts (carries e.g. tailscale's vendorHash fix).
          { nixpkgs.overlays = [ overlayFixes ]; }
          sops-nix.nixosModules.sops
          ./hosts/homeserver.nix
          disko.nixosModules.disko
          ./hosts/homeserver-disk.nix
        ];
      };

      # Tool set to run from rootless Nix (nix-portable) on an SSH target.
      # Supports both Linux x86_64 / aarch64.
      remoteTools =
        pkgs': with pkgs'; [
          # The zsh set, to get the same experience as the main Mac (ghost-text completion /
          # syntax highlighting / fzf-tab) remotely. configs/shell/zshrc.remote reads them
          # straight from the store (home-manager can't run on the remote).
          zsh
          zsh-autosuggestions
          zsh-syntax-highlighting
          zsh-fzf-tab
          zsh-history-substring-search
          starship
          neovim
          yazi
          tmux
          # herdr comes from the same nixpkgs-agents as the main Mac (neither the stable 26.05
          # series nor nixpkgs-unstable). `herdr --remote` refuses to attach unless both ends are
          # the same build, and on a version mismatch the client drops its own copy into
          # ~/.local/bin. Keeping it in remote-env lets the flake pin align both ends, so that
          # fallback never fires (pairs with agentPkgs.herdr in modules/home/packages.nix).
          nixpkgs-agents.legacyPackages.${pkgs'.stdenv.hostPlatform.system}.herdr
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
            # .shellcheckrc says severity=error, but it has no effect. The shellcheck 0.11 rc
            # only honors disable= and the like; severity is CLI-only (measured: disable=SC2001
            # in the same rc works, while severity=error is ignored, style findings still show,
            # and it exits 1). So the intent "gate on error level only" was never realized.
            # Pass it again here.
            args = [ "--severity=error" ];
            excludes = [
              # Symlinks into another repository (gapul/ai-agent-state). The link is committed,
              # the target is not, so in CI there is nothing behind it and shellcheck stops with
              # "openBinaryFile: does not exist" — which reads like a lint failure but is a
              # missing file. Anything under here is linted where it actually lives.
              "configs/cli/codex/.*"
              # The sketchybar configs stylistically use a lot of intentional word splitting, handled separately
              # (manual check: nix develop ./nix -c shellcheck configs/wm/sketchybar/...)
              "configs/wm/sketchybar/.*"
              # direnv files have no shebang and assume the direnv stdlib
              "\\.envrc$"
              # zsh is out of scope for shellcheck (SC1071). Excluded by extension because adding
              # directories one by one, like macmini below, misses things. configs/shell/*.zsh
              # had in fact slipped through, and `just fmt` failed with SC1072 even on
              # origin/main. Both `f() { x=$y }` in prompt.zsh and `${${x}}` in evalcache.zsh
              # are valid zsh that shellcheck just can't read, so rewriting them to silence it
              # is the wrong fix.
              "\\.zsh$"
              # Some zsh has no extension. The macmini AI commands are zsh only by shebang
              "configs/macmini/bin/.*"
              # Same for their main-Mac-side client wrappers
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
        # aarch64-linux is not here. The only thing it ever built was the
        # gapul-linux-aarch64 home config, which exists for a plain ARM Linux box — the
        # Raspberry Pi, retired 2026-08-24. Nothing has run it since, and building a
        # configuration no machine uses cost 116s of every pull request.
        #
        # The configuration itself stays: bootstrap-linux.sh picks it by architecture, so it is
        # the path a future ARM box would come up on, and it is a parameterisation of the same
        # home config rather than anything to maintain separately. Put "aarch64-linux" back here
        # and in scripts/ci-plan-systems.sh when such a machine exists.
        #
        # nix-on-droid is aarch64-linux too but is unaffected: it is a top-level output built
        # through its own app with --impure and the nix-on-droid substituter, never through this
        # matrix.
        systems = [
          system
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

              # iOS configuration profiles. The contents are just generated XML, so they build on any
              # system. mobile/ios/profiles/serve.sh reads this output to deliver them to devices.
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
                  # AquesTalkPlayer's licensed DMG is intentionally requireFile and cannot be
                  # fetched by CI. Build the same workstation with only manual sources disabled;
                  # the deployed darwinConfiguration below keeps them enabled.
                  (darwinWorkstation false).system
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
              # Exported so other flakes (laya-drive) can take `laya-python` from here.
              laya-mlx = systemPkgs.callPackage ./pkgs/laya-mlx.nix { };
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
            devShells = {
              default = systemPkgs.mkShell (
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
            # Ladybird and Servo build with Xcode's clang against the macOS SDK,
            # so those two shells only exist on darwin. They are entered by hand
            # rather than built by CI: the engines take hours and tens of GB.
            // lib.optionalAttrs isDarwinWorkstation (
              import ./shells/browser-engines.nix { pkgs = systemPkgs; }
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
                # hosts/homeserver.nix pulls in homelab/formera.nix, which takes the
                # source as a module argument. nixosConfigurations.homeserver passes it
                # the same way; without it here the VM test stops evaluating with
                # "attribute 'formera-source' missing".
                inherit user formera-source;
                sopsNix = sops-nix;
                # nixpkgs-nixos, not systemPkgs: runNixOSTest takes its NixOS module
                # set from whichever nixpkgs pkgs came from, and systemPkgs is built
                # from the 26.05-darwin lineage. hosts/homeserver.nix is deployed
                # against nixos-unstable, so options that only exist there made the
                # test fail to evaluate while the real config was fine
                # (services.journald.settings was the one that caught this).
                pkgs = nixpkgs-nixos.legacyPackages.${system};
              };
            };
          };
      };
    in
    perSystemOutputs
    // {
      # System config: sudo darwin-rebuild switch --flake .#<username>
      darwinConfigurations.${user.username} = darwinWorkstation true;

      # Headless LLM worker (M4 Mac mini / 24GB):
      #   sudo darwin-rebuild switch --flake .#macmini
      # A minimal config that shares the same common.nix as the workstation but adds no GUI casks.
      # sops lives on the system side here rather than in home-manager, decrypting with the box's
      # own SSH host key (hosts/macmini.nix). The old "no sops on the macmini" policy was really a
      # policy of not copying the human age master key onto an unattended machine; a host key that
      # was already here and only opens secrets/common.yaml does not violate it.
      darwinConfigurations.macmini = mkHost.darwin {
        host = ./hosts/macmini.nix;
        homeModules = roles.macminiHeadless;
        specialArgs = {
          inherit user;
          # hosts/macmini.nix and its home layer both take this; without it the whole macmini
          # configuration stops evaluating, which is where it was found — nothing in CI builds
          # this closure, so it went unnoticed until something needed the mini again.
          nixpkgsAgents = nixpkgs-agents;
          claudeAcp = claude-acp.packages.${system}.default;
          sopsNix = sops-nix;
          # The side that receives remote builds from the main Mac. If the connecting user isn't in
          # trusted-users, nix refuses with "can't trust the derivations it was handed".
          #
          # darwin-common.nix says "avoid trusted-user since it is root-equivalent, and apply
          # substituters to all users via a root-owned line". That is about not escalating just to
          # add a cache; for remote builds the escalation is what the feature itself requires,
          # so it can't be avoided.
          #
          # The escalation means "anyone who can ssh in as gapul can touch the macmini's nix store
          # as root". Being able to ssh in as gapul already allows a lot, so the increment is
          # small. But since the policy is written down, the reason is recorded here.
          nixCustomConf = {
            trusted-users = "root ${user.username}";
            # darwin-common's max-jobs 4 x cores 2 is sized for the laptop (8 logical cores,
            # 16 GB). Applied here it left one large derivation, the kind this machine exists
            # to take, on two of its ten cores (an Azahar build ran as `make -j2`). 2 x 4 keeps
            # the same ceiling of eight compiler processes, which matters because the resident
            # models already hold most of the 24 GB, but gives a single big build four cores.
            max-jobs = "2";
            cores = "4";
          };
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
            specialArgs = {
              inherit user;
              nixpkgsAgents = nixpkgs-agents;
              # Must be passed here, not defaulted in the module signature: the host
              # uses it inside `imports`, and resolving a module argument from
              # `_module.args` there needs `config`, which is infinite recursion.
              hardwareConfig = ./hosts/nixos-laptop-hardware.nix;
            };
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
              home-manager-nixos.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs = commonSpecialArgs;
                home-manager.users.${user.username} = {
                  imports = [
                    ./home/common.nix
                    ./home/linux.nix
                    ./home/hyprland.nix # Hyprland rice (nixos-laptop only)
                    stylix.homeModules.stylix
                    ./home/stylix.nix # one palette for GTK/Qt/wofi (nixos-laptop only)
                    ./home/ssh-tpm-agent.nix # TPM-sealed SSH key (nixos-laptop only: WSL has no TPM)
                    ./home/linux-gui.nix # GUI apps (the mac's cask list, as packages)
                    # programs.firefox.arkenfox for modules/home/firefox.nix (imported by linux-gui.nix)
                    inputs.arkenfox.modules.homeManager.arkenfox
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
              nixpkgsAgents = nixpkgs-agents;
              hardwareConfig = ./hosts/nixos-laptop-hardware-ci.nix;
            };
            modules = [
              # SSO overlay absorbing upstream nixpkgs breakage (shared with darwin/standalone home).
              # Override things like tailscale's wrong vendorHash here.
              { nixpkgs.overlays = [ overlayFixes ]; }
              ./hosts/nixos-laptop.nix
              lanzaboote.nixosModules.lanzaboote
              home-manager-nixos.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs = commonSpecialArgs;
                home-manager.users.${user.username}.imports = [
                  ./home/common.nix
                  ./home/linux.nix
                  ./home/hyprland.nix
                  # Kept in step with the real host's list: without these two, CI would build
                  # a laptop whose desktop is themed differently from the one that ships, and
                  # a broken stylix option would only surface at rebuild time on the machine.
                  stylix.homeModules.stylix
                  ./home/stylix.nix
                  ./home/dev.nix
                  ./home/ssh-tpm-agent.nix
                  # The GUI app list and the shared Firefox profile. Possible since Zen (which
                  # needed an extra module argument) left on 2026-10-01.
                  ./home/linux-gui.nix
                  inputs.arkenfox.modules.homeManager.arkenfox
                  ./home/workstation.nix
                ];
              }
            ];
          };

          # NixOS inside Windows (WSL2). Build a tarball and install it with wsl --import:
          #   sudo nix run <flake>#nixosConfigurations.wsl.config.system.build.tarballBuilder
          # It doesn't share an install with the real dual-boot NixOS (WSL2 can't boot a physical
          # partition). What it shares is the home-side roles.wsl.
          "wsl" = nixpkgs-nixos.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit user; };
            modules = [
              { nixpkgs.overlays = [ overlayFixes ]; }
              nixos-wsl.nixosModules.default
              ./hosts/wsl.nix
              home-manager-nixos.nixosModules.home-manager
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
      # Rootless-docker container on a shared machine: .#<username>-linux-shared. Only its
      # config.home.path is built there (configs/bin/nixsh); never activated. See docs/CHEATSHEET.md.
      homeConfigurations."${user.username}-linux-shared" = mkHost.home {
        targetSystem = "x86_64-linux";
        modules = roles.linuxShared;
      };
    };
}
