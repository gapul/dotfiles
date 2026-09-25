{
  pkgs,
  user,
  # このホストだけ /etc/nix/nix.custom.conf に足したい設定。
  #
  # 分けて書けないのは、activation がマーカー間を丸ごと再生成するため。ホストごとに
  # 別々の追記をすると片方が消える。共有の settings と混ぜて 1 ブロックにする。
  nixCustomConf ? { },
  ...
}:
{
  # Host-independent base settings shared by the workstation (darwin.nix) and the
  # headless LLM worker (macmini.nix). Changes here affect both hosts.
  # GUI/peripheral-oriented settings (dock/finder/trackpad/fonts/homebrew) live on each host side.

  nixpkgs.config.allowUnfree = true;

  # overlay to absorb temporary breakage in upstream nixpkgs (SSO: shared with flake.nix's mkPkgs).
  # Since useGlobalPkgs makes the embedded home-manager use this pkgs too, without this
  # the darwin system's pre-commit stays vanilla → isatty breakage recurs under om ci (aarch64-darwin).
  # Merges with the brewNix overlay on the darwin.nix side via list concatenation.
  nixpkgs.overlays = [ (import ../lib/overlays.nix) ];

  # Determinate Nix manages the daemon/nix.conf, so nix-darwin doesn't touch it
  nix.enable = false;

  # Own the Homebrew installation, not just the package list. nix-darwin's homebrew module
  # (the brews/casks lists on each host) assumes /opt/homebrew was put there by hand — which is
  # the one step of this repo a fresh mac could not reproduce.
  #
  # autoMigrate: adopt the existing /opt/homebrew instead of demanding an empty prefix. The
  #   installed formulae and casks stay where they are; only ownership of the prefix moves.
  # mutableTaps: left on. Pinning taps as flake inputs would also freeze `brew update`, and
  #   _upgrade-packages-macos in the Justfile runs exactly that before upgrading — the tap trust
  #   dance there only makes sense against a mutable tap set. Revisit if tap drift ever bites.
  nix-homebrew = {
    enable = true;
    user = user.username;
    enableRosetta = false; # Apple Silicon only; no x86_64 prefix to manage
    autoMigrate = true;
    mutableTaps = true;
  };

  # Determinate Nix owns /etc/nix/nix.conf and does `!include nix.custom.conf`, so nix-darwin's
  # typed `nix.settings` is unavailable (nix.enable = false above) and this file is where our
  # settings have to land. It used to be five append-if-grep-misses blocks, which could only ever
  # add lines: rotating a cache key left the old line in place and the file grew every time.
  # Now the whole block between the markers is regenerated each activation, so entries can change
  # and disappear. Everything outside the markers (Determinate's own lines, e.g. FlakeHub) is left
  # untouched.
  system.activationScripts.postActivation.text =
    let
      # Public caches to pull from. Substituter-only on purpose: making the user a trusted-user
      # would be root-equivalent, whereas a root-owned entry here grants exactly one cache.
      caches = {
        # nix-community: for the flake inputs that publish there
        "https://nix-community.cachix.org" =
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
        # nix-on-droid: prebuilts like proot-termux come only from the official cachix
        "https://nix-on-droid.cachix.org" =
          "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU=";
        # this config's own outputs, pushed by CI, so `just rebuild` doesn't rebuild them locally
        "https://gapul-dotfiles.cachix.org" =
          "gapul-dotfiles.cachix.org-1:tGNGJ7SGHrLAjswSIz673st0AepuNjQombMJO0VUq98=";
      };
      settings = {
        # Keeps nix-env / nix-instantiate (used internally by home-manager and nix-darwin for
        # profile operations) from regenerating ~/.nix-defexpr and ~/.nix-channels in $HOME.
        use-xdg-base-directories = "true";
        # With the default 15s narinfo wait and fallback=false, an unreachable substituter is fatal
        # instead of falling back to a source build (a tailnet-only attic going down once caused
        # real damage). Give up early and escape to building from source.
        connect-timeout = "5";
        fallback = "true";
        # This machine has 8 logical cores (4 performance + 4 efficiency). The defaults are
        # max-jobs = auto (= 8) and cores = 0 (= all cores per job), so up to eight derivations
        # each try to use eight threads. Combined with the QoS clamp in `just rebuild`, that is
        # 64 threads fighting over four efficiency cores, and the scheduling overhead costs more
        # than the parallelism gains. 4 x 2 keeps the total at the core count.
        max-jobs = "4";
        cores = "2";
        # GC がビルド時にしか要らない依存 (dmg や wheel の取得物、ツールチェーン) まで消すと、
        # 次の rebuild / CI がそれを全部取り直す (macmini の週次 GC 直後に pr-gate が 10 分超えた)。
        # keep-derivations (既定 true) と組で、生きている出力の .drv が参照する入力を GC 対象から
        # 外す。消えるのは本当に何からも参照されないものだけになる。
        keep-outputs = "true";
        extra-substituters = builtins.concatStringsSep " " (builtins.attrNames caches);
        extra-trusted-public-keys = builtins.concatStringsSep " " (builtins.attrValues caches);
      }
      // nixCustomConf;
      # Written as a store file and cat'd in: no heredoc quoting to get wrong.
      block = pkgs.writeText "nix-custom-conf-block" (
        ''
          # >>> nix-darwin managed (hosts/darwin-common.nix) — do not edit between the markers
        ''
        + builtins.concatStringsSep "\n" (
          builtins.attrValues (builtins.mapAttrs (k: v: "${k} = ${v}") settings)
        )
        + ''

          # <<< nix-darwin managed
        ''
      );
    in
    ''
        # Rewrite the managed block of nix.custom.conf (delimited by the markers in it).
        conf=/etc/nix/nix.custom.conf
        if [ -f "$conf" ]; then
          /usr/bin/sed -i.bak '/# >>> nix-darwin managed/,/# <<< nix-darwin managed/d' "$conf"
          /bin/rm -f "$conf.bak"
          printf '\n' >> "$conf"
          /bin/cat ${block} >> "$conf"
        fi
        # Determinate Nix already trusts FlakeHub as a substituter, but using it as an
        # active substituter without the matching credentials produces 401 warnings.
        if [ -f "$conf" ] && /usr/bin/grep -q 'cache.flakehub.com' "$conf"; then
          /usr/bin/sed -i.bak '/cache\.flakehub\.com/d' "$conf"
          /bin/rm -f "$conf.bak"
        fi
      # Application Firewall: enable + stealth mode (no response to ping/port scans).
      # alf defaults barely works on recent macOS, so idempotently invoke the official socketfilterfw.
      fw=/usr/libexec/ApplicationFirewall/socketfilterfw
      "$fw" --setglobalstate on >/dev/null 2>&1 || true
      "$fw" --setstealthmode on >/dev/null 2>&1 || true
      # (automatic security updates moved to system.defaults.CustomSystemPreferences below)
    '';

  system.stateVersion = 5;
  system.primaryUser = user.username;

  # Authenticate sudo with Touch ID (sudo_local is the official mechanism that survives macOS updates)
  # reattach: inside multiplexers like tmux/screen the session is detached from the GUI
  # and pam_tid can't show the Touch ID dialog. Prepend pam_reattach (nixpkgs) as
  # auth optional to reattach to the user's bootstrap session, which fixes it.
  # (Harmless on a Mac mini with no Touch ID sensor: it just falls back to password auth)
  security.pam.services.sudo_local = {
    reattach = true;
    touchIdAuth = true;
  };

  # The sketchybar nosleep item toggles pmset on click, and sketchybar has no way to ask
  # for a password. Allow exactly the two commands it runs, so the click is a plain toggle
  # instead of an auth dialog every time. Nothing else gains privileges.
  security.sudo.extraConfig = ''
    ${user.username} ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
  '';

  users.users.${user.username} = {
    name = user.username;
    home = "/Users/${user.username}";
    shell = pkgs.zsh;
  };

  programs.zsh = {
    enable = true;
    # /etc/zshrc runs before the home-manager .zshrc and was redoing work it does better:
    #   - a full compinit (compaudit + a second dump under ~/.config/zsh) while
    #     modules/home/shell.nix already runs a cached `compinit -C` against ~/.cache/zsh
    #   - `prompt suse`, which starship overwrites two lines later
    # Under load these cost hundreds of ms per shell, and neither leaves anything behind.
    # bashcompinit moves with it: it needs a compinit to have run first, so it now sits
    # right after the cached one in modules/home/shell.nix.
    enableCompletion = false;
    enableBashCompletion = false;
    promptInit = "";
  };
  environment.shells = [ pkgs.zsh ];

  # host-independent macOS settings (keyboard/login/privacy).
  # GUI/peripheral-oriented ones like dock/finder/trackpad are declared on each host side.
  system.defaults = {
    # Automatic security updates. These keys have no typed nix-darwin option, but
    # CustomSystemPreferences is the declared form of the same /Library/Preferences write —
    # it does not need a hand-rolled `defaults write` loop in postActivation.
    # Keeps XProtect/MRT and security responses current even if the machine is left alone.
    CustomSystemPreferences = {
      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;
        AutomaticDownload = true;
        CriticalUpdateInstall = true; # security responses / XProtect
        ConfigDataInstall = true; # XProtect / MRT definitions
      };
      "com.apple.commerce".AutoUpdate = true;
    };
    NSGlobalDomain = {
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      AppleShowScrollBars = "WhenScrolling";
      NSDocumentSaveNewDocumentsToCloud = false; # don't upload new documents to iCloud by default
      # Note: Caps→Esc is handled by Karabiner, so not declared here
      # Note: AppleInterfaceStyle (Dark mode) is not explicitly set, so excluded
    };
    # require password immediately after sleep/screensaver (anti-shoulder-surfing when away. was 300s)
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };
    # (automatic security updates are system-level, so done via defaults write in postActivation)
    # login screen hardening
    loginwindow = {
      GuestEnabled = false; # disable guest account
      SHOWFULLNAME = true; # no user list, enter name+password (anti account enumeration)
      DisableConsoleAccess = true; # forbid ">console" console login
    };
    # disable browser telemetry (declare enterprise policy via defaults)
    CustomUserPreferences = {
      # disable Apple's personalized (targeted) ads
      "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
      # don't write .DS_Store to network shares / USB (local can't be suppressed, Finder behavior)
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.google.Chrome" = {
        MetricsReportingEnabled = false;
        # 1 = never download the on-device foundational model (Gemini Nano).
        # It sits unused in Application Support at ~4GB, so keep it off the disk.
        GenAILocalFoundationalModelSettings = 1;
      };
    };
  };

  # Nix store GC as root, weekly. The user-side GC (home/maintenance.nix, home/macmini-maintenance.nix)
  # can only drop home-manager generations; /nix/var/nix/profiles/system-* is root-owned and kept
  # piling up (macmini: 141 generations / 114G on 2026-09-23; workstation: 26 generations in two
  # weeks, /nix free 123G -> 23G over July-September 2026).
  #
  # The program is a signed copy of `nix` at a stable path (home/nix-gc-tcc.nix), not the store
  # binary, because TCC stamps `com.apple.macl` on .app bundles the user has opened (OmniWM,
  # Keystats, terminal-browser's Electron, ...). chmod on such a directory is refused for any process
  # without Full Disk Access, root included, and the GC then aborts with "0 store paths deleted"
  # (this is what silently broke both machines' GC in September 2026; `xattr -d com.apple.macl`
  # from a root daemon is refused the same way, so stripping the label is not an option).
  # The copy is invoked directly, no shell wrapper: TCC attributes the chmod to the launchd
  # program, and /bin/sh is not the thing we want to hand Full Disk Access to.
  #
  # One-time per machine: System Settings > Privacy & Security > Full Disk Access >
  # add ~/.local/libexec/tcc/nix-collect-garbage. Until then the daemon runs but GC still
  # stops at the first macl-tagged bundle; check /var/log/nix-gc.log for "0 store paths deleted".
  #
  # 7d, not 30d, and no generation count: `nix-collect-garbage` can only express an age, and
  # the program has to stay this binary invoked directly (a wrapper would be the thing TCC
  # grants Full Disk Access to), so `nh clean all --keep 5` — what `just gc` uses by hand — is
  # not available here. 30d never freed anything: these machines rebuild about three times a
  # day, so the window held roughly 90 system closures at once (macmini on 2026-09-25: 97
  # generations, 137G used, oldest exactly 30 days old, so a run would have dropped one).
  # A week still leaves ~13 generations to roll back to.
  #
  # Sunday 03:45: before the user-side cleanups (04:15) and restic (05:00).
  launchd.daemons.nix-gc = {
    serviceConfig = {
      ProgramArguments = [
        "/Users/${user.username}/.local/libexec/tcc/nix-collect-garbage"
        "--delete-older-than"
        "7d"
      ];
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 3;
          Minute = 45;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/var/log/nix-gc.log";
      StandardErrorPath = "/var/log/nix-gc.log";
    };
  };

  # Store deduplication, right after the GC. Neither machine had ever been optimised: the first
  # manual run on 2026-09-26 freed 10G on the workstation and ~30G on macmini. auto-optimise-store
  # is left off because nix-darwin still warns it can corrupt the store on macOS (NixOS/nix#7273).
  #
  # Same executable as nix-gc, so the one Full Disk Access grant covers both jobs. The binary is
  # multi-call and dispatches on argv[0], and launchd lets Program (the file TCC looks at) and
  # ProgramArguments[0] (what nix sees) differ, so no wrapper is needed here either.
  launchd.daemons.nix-store-optimise = {
    serviceConfig = {
      Program = "/Users/${user.username}/.local/libexec/tcc/nix-collect-garbage";
      ProgramArguments = [
        "nix"
        "store"
        "optimise"
      ];
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 4;
          Minute = 0;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
      StandardOutPath = "/var/log/nix-store-optimise.log";
      StandardErrorPath = "/var/log/nix-store-optimise.log";
    };
  };
}
