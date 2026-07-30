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

  # Determinate's nix.conf does `!include nix.custom.conf`, so idempotently write
  # use-xdg-base-directories there. This keeps nix-env / nix-instantiate
  # (used internally by home-manager / nix-darwin for profile operations) from regenerating
  # ~/.nix-defexpr / ~/.nix-channels in $HOME, moving them under ~/.local/state/nix/ instead.
  # nix-darwin does not run arbitrarily-named system.activationScripts.<name>. Consolidate into
  # postActivation, which runs as root at the end of activation.
  system.activationScripts.postActivation.text = ''
    # idempotently append use-xdg-base-directories to nix.custom.conf (keeps nix-env from regenerating
    # ~/.nix-defexpr / ~/.nix-channels in $HOME, moving them under ~/.local/state/nix/ instead).
    conf=/etc/nix/nix.custom.conf
    if [ -f "$conf" ] && ! /usr/bin/grep -q '^use-xdg-base-directories' "$conf"; then
      printf '\n# XDG Base Directory compliance (moves ~/.nix-defexpr etc. under ~/.local/state/nix)\nuse-xdg-base-directories = true\n' >> "$conf"
    fi
    # general safeguard so an unreachable substituter doesn't break builds. With the default 15s
    # narinfo-fetch wait and fallback=false, a substitute failure fails fatally instead of falling
    # back to a source build (a tailnet-only attic going down once caused real damage). connect-timeout
    # gives up early and fallback=true escapes to a source build. Pull behavior when reachable is unchanged.
    if [ -f "$conf" ] && ! /usr/bin/grep -q '^connect-timeout' "$conf"; then
      printf '\n# make unreachable substituters non-fatal (builds still pass even if the cache is down)\nconnect-timeout = 5\nfallback = true\n' >> "$conf"
    fi
    # Trust the nix-community cache system-wide.
    # Security least-privilege: rather than making yuki a trusted-user (effectively root-equivalent), append
    # only the specific substituter + its public key to the root-owned nix.custom.conf. This silences the flake
    # nixConfig 'ignoring untrusted substituter' warning without granting the user broad privileges.
    if [ -f "$conf" ] && ! /usr/bin/grep -q 'nix-community.cachix.org' "$conf"; then
      printf '\n# nix-community binary cache (least privilege: substituter-only, not a trusted-user grant)\nextra-substituters = https://nix-community.cachix.org\nextra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=\n' >> "$conf"
    fi
    # nix-on-droid: prebuilts like proot-termux can only be fetched from the official cachix
    if [ -f "$conf" ] && ! /usr/bin/grep -q 'nix-on-droid.cachix.org' "$conf"; then
      printf '\n# nix-on-droid binary cache (for eval/build of the droid config)\nextra-substituters = https://nix-on-droid.cachix.org\nextra-trusted-public-keys = nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU=\n' >> "$conf"
    fi
    # self-made dotfiles build cache (cachix gapul-dotfiles, OSS free tier). Pull this config's
    # outputs, pushed by CI, from here to speed up local jd rebuild.
    # It's a public cache so pull is unauthenticated. Falls back to cache.nixos.org even if unreachable.
    if [ -f "$conf" ] && ! /usr/bin/grep -q 'gapul-dotfiles.cachix.org' "$conf"; then
      printf '\n# self-made dotfiles build cache (cachix, filled by CI, unauthenticated pull)\nextra-substituters = https://gapul-dotfiles.cachix.org\nextra-trusted-public-keys = gapul-dotfiles.cachix.org-1:tGNGJ7SGHrLAjsw5Iz673st0AepuNjQombMJOOVUq98=\n' >> "$conf"
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
    # automatic security updates (system-level defaults. nix-darwin has no typed option, so
    # write directly in root's postActivation). Keeps XProtect/MRT and security responses current even if left alone.
    su=/Library/Preferences/com.apple.SoftwareUpdate
    /usr/bin/defaults write "$su" AutomaticCheckEnabled -bool true   >/dev/null 2>&1 || true
    /usr/bin/defaults write "$su" AutomaticDownload     -bool true   >/dev/null 2>&1 || true
    /usr/bin/defaults write "$su" CriticalUpdateInstall -bool true   >/dev/null 2>&1 || true  # security responses/XProtect
    /usr/bin/defaults write "$su" ConfigDataInstall     -bool true   >/dev/null 2>&1 || true  # XProtect/MRT definitions
    /usr/bin/defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true >/dev/null 2>&1 || true
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
      };
    };
  };
}
