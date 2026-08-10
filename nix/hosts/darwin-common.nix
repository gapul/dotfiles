{ pkgs, user, ... }:
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
          "gapul-dotfiles.cachix.org-1:tGNGJ7SGHrLAjsw5Iz673st0AepuNjQombMJOOVUq98=";
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
        extra-substituters = builtins.concatStringsSep " " (builtins.attrNames caches);
        extra-trusted-public-keys = builtins.concatStringsSep " " (builtins.attrValues caches);
      };
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
  # reattach: inside multiplexers like zellij/tmux/screen the session is detached from the GUI
  # and pam_tid can't show the Touch ID dialog. Prepend pam_reattach (nixpkgs) as
  # auth optional to reattach to the user's bootstrap session, which fixes it.
  # (Harmless on a Mac mini with no Touch ID sensor: it just falls back to password auth)
  security.pam.services.sudo_local = {
    reattach = true;
    touchIdAuth = true;
  };

  users.users.${user.username} = {
    name = user.username;
    home = "/Users/${user.username}";
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;
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
}
