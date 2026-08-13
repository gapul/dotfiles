{
  config,
  pkgs,
  lib,
  user,
  nixpkgsUnstable,
  ...
}:
let
  # For creative tools whose official binaries are paid but nixpkgs source builds are free & full.
  # On 26.05-darwin ardour/aseprite are unavailable/broken, so use nixos-unstable, and
  # re-instantiate with allowUnfree since aseprite is unfree.
  unstablePkgs = import nixpkgsUnstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

  # Bound here rather than inline in home.packages because the LaunchAgent below
  # needs the path too, and both must point at the same store path.
  mechvibes-dx = pkgs.callPackage ../pkgs/mechvibes-dx.nix { };
in
{
  imports = [
    ../modules/home/darwin-chrome.nix
    ../modules/home/darwin-services.nix
    ../modules/home/darwin-apps.nix
    ../modules/home/darwin-ai-client.nix
  ];

  # macOS-specific home-manager config
  # Common parts are split into home/common.nix

  home.homeDirectory = "/Users/${user.username}";

  home.sessionVariables = {
    HOMEBREW_NO_ANALYTICS = "1";
    # What `brew shellenv` used to export, declared instead of spawning brew every shell.
    # See the interactiveShellInit override in hosts/darwin.nix for why it is gone.
    # Its PATH work was already redundant (home.sessionPath + /etc/zprofile's path_helper
    # produce a byte-identical PATH), so only these are left.
    # ponytail: pinned to the /opt/homebrew prefix this machine has. If brew ever moves or
    #           starts exporting something new, `brew shellenv` is the thing to diff against.
    HOMEBREW_PREFIX = "/opt/homebrew";
    HOMEBREW_CELLAR = "/opt/homebrew/Cellar";
    HOMEBREW_REPOSITORY = "/opt/homebrew/Library/.homebrew-is-managed-by-nix";
    INFOPATH = "/opt/homebrew/share/info:";
    # NOTE: brew's trust.json can't be XDG-ified. The activation brew bundle
    # strips XDG_CONFIG_HOME via `sudo --preserve-env=PATH --set-home` and always reads ~/.homebrew.
    # Also, brew prefers XDG_CONFIG_HOME over HOMEBREW_USER_CONFIG_HOME, so the interactive shell's
    # plain trust drifted to ~/.config/homebrew and got duplicated. The
    # `.config/homebrew → ~/.homebrew` symlink below converges both paths onto the same entity
    # (Justfile rebuild's `env -u XDG_CONFIG_HOME` is harmless, so kept).
    PNPM_HOME = "${config.home.homeDirectory}/Library/pnpm";
    # nh: darwin works with the darwinConfigurations.<user> form. For home on nh 4.3.2,
    # neither #name nor #...activationPackage works → flake only (no #) so it auto-detects
    # homeConfigurations.<user> by user name is the only form that works.
    NH_DARWIN_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix#darwinConfigurations.${user.username}";
    NH_HOME_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix";
  };

  # Resolve brew trust.json duplication: converge the interactive shell (reads
  # ~/.config/homebrew via XDG_CONFIG_HOME priority) and the sudo/rebuild path (~/.homebrew)
  # onto the same entity via symlink. Canonical is ~/.homebrew (the sudo side doesn't see XDG).
  home.file.".config/homebrew".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.homebrew";

  # Move real data of non-XDG tools under XDG, keep default paths via symlink
  # (same approach as terminfo). Classification: credentials/long-term data=data, telemetry state=state.
  home.file.".appstoreconnect".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/appstoreconnect";
  home.file.".cloudflared".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/cloudflared";
  home.file.".ollama".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/ollama";
  home.file.".dart-tool".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/dart-tool";
  # Ensure the entity exists first, else tool writes fail with ENOENT when the symlink target is missing
  home.activation.xdgSymlinkTargets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p \
      "${config.xdg.dataHome}/appstoreconnect" \
      "${config.xdg.dataHome}/cloudflared" \
      "${config.xdg.dataHome}/ollama" \
      "${config.xdg.stateHome}/dart-tool"
  '';

  home.sessionPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "${config.home.homeDirectory}/Library/pnpm"
    "${config.home.homeDirectory}/Library/pnpm/bin"
  ];

  # The other half of what `brew shellenv` did: its zsh completions (_deno, _ghostty, _mpv,
  # _tailscale, _yt-dlp …). mkBefore puts it ahead of the compinit in modules/home/shell.nix,
  # which is the only ordering that matters here.
  programs.zsh.completionInit = lib.mkBefore ''
    fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
  '';

  # Append Mac-specific zsh init (added after common's initContent)
  programs.zsh.initContent = lib.mkAfter ''
    # (No brew shellenv here: /etc/zshrc runs one before this file is read, and by then
    #  /opt/homebrew/bin leads PATH, so a second call always returned an empty string.
    #  It was one process spawn per shell for nothing.)

    # Package manager priority (nix > homebrew) applied to PATH itself: brew shellenv prepends
    # /opt/homebrew/bin, which used to put brew ahead of the nix profile, so anything present on both
    # sides silently resolved to brew. Re-prepend the nix profiles after it. typeset -U keeps the
    # first occurrence and drops the later duplicates, so brew stays available, just behind nix.
    # (Only zsh is covered. Non-shell contexts — launchd agents / GUI apps — still follow
    #  home.sessionPath, where brew comes first. The invariant test in tests/config-invariants.nix
    #  is what actually keeps duplicates from existing in the first place.)
    typeset -U path PATH
    path=(
      "$HOME/.local/state/nix/profile/bin"
      /run/current-system/sw/bin
      /nix/var/nix/profiles/default/bin
      $path
    )

    # Bitwarden SSH agent: prefer the socket Desktop (direct-DL build) creates when enabled.
    # Keys are stored in the Bitwarden Vault; Desktop approves each connection (Touch ID).
    # To avoid breaking when Bitwarden isn't running/enabled, fall back to launchd default when the socket is absent.
    if [[ -S "$HOME/.bitwarden-ssh-agent.sock" ]]; then
      export SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"
    fi

    # CocoaPods (avoid conflict with nix ruby)
    unset GEM_HOME GEM_PATH

    # sketchybar reconfigure wrapper (call after plugging/unplugging displays)
    function sketchybar-refresh() {
      bash ~/.config/sketchybar/helpers/refresh-displays.sh "$@"
    }

    # Toggle to temporarily disable clamshell sleep.
    # Use when you want processing to keep running with the lid closed.
    # Temporary setting reset on reboot. Use off to return to normal.
    function nosleep() {
      case "$1" in
        off)
          sudo pmset -a disablesleep 0 && echo "Sleep disable removed (back to normal sleep)"
          ;;
        status|"")
          if pmset -g | grep -q "SleepDisabled.*1"; then
            echo "Current: sleep disabled (keeps running with the lid closed)"
          else
            echo "Current: normal (sleeps when the lid is closed)"
          fi
          ;;
        on)
          sudo pmset -a disablesleep 1 && echo "Sleep disabled (keeps running with the lid closed / power connection recommended)"
          ;;
        *)
          echo "Usage: nosleep [on|off|status]"
          ;;
      esac
    }
  '';

  # mac-specific packages
  home.packages = with pkgs; [
    bun # generate/type-check karabiner.ts config
    brewCasks.qview # brew-nix test target: lightweight image viewer distributed as a simple .app
    pngpaste # needed for macOS image paste in obsidian.nvim / img-clip
    syncthing # Syncthing CLI (the resident is the LaunchAgent in services.syncthing)
    xcodegen # generate .xcodeproj from project.yml (Mac-only, since meta.platforms = darwin in Linux nixpkgs)
    (callPackage ../pkgs/slk.nix { }) # Slack TUI (pinned to the official GitHub Release)
    # sketchybar's event helper. `sketchybarrc` used to compile it on every bar start from
    # sources kept in the config directory; the launchd agents put the profile first on PATH.
    (callPackage ../pkgs/sketchybar-helper { })
    # MechvibesDX (keyboard sounds): upstream's macOS DMG SIGTRAPs on the first
    # keypress, so it is built here with the rdev fix. See pkgs/mechvibes-dx.nix.
    # Needs Accessibility permission, and because TCC keys on the executable's
    # path, that has to be re-granted whenever the store path changes.
    mechvibes-dx
    # zrythm (DAW): broken=isDarwin in nixpkgs. Self-built for darwin with carla included.
    # See pkgs/zrythm-darwin/ for details. GUI must be launched in a foreground GUI session.
    # On 26.05-darwin appstream/libadwaita can't build on darwin, so this one package alone
    # uses nixos-unstable pkgs (nixpkgsUnstable, via commonSpecialArgs in flake.nix).
    (import ../pkgs/zrythm-darwin {
      pkgs = nixpkgsUnstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
    })
    # ─── Creative: official is paid but nixpkgs source builds give a free full version ───
    # Unavailable/broken on 26.05-darwin, so from unstablePkgs (nixos-unstable, with allowUnfree).
    unstablePkgs.fritzing # PCB/circuit design CAD (official DL is paid. for the ESP32 project). cached, so instant
    unstablePkgs.ardour # DAW (official binary is pay-what-you-want. free via source build). cached, so instant
    unstablePkgs.aseprite # pixel-art editor (official $20. source-available/self-built is free full)

    # ─── CLI migrated from Homebrew (stage 4: mac CLI that had no reason to stay on brew) ───
    # All of these exist in nixpkgs for aarch64-darwin and substitute from the cache, and none of
    # them needs a brew service / tap / keg. See hosts/darwin.nix's brews for what stays on brew and why.
    sox # audio processing (rec / play / sox / soxi)
    exiftool # strip metadata (GPS/device info) from images/PDFs before sharing
    blueutil # Bluetooth CLI
    duti # file associations
    scrcpy # Android screen mirroring
    swi-prolog # Prolog (functional/logic programming lab. nvim ftplugin expects swipl on PATH)
    tcpdump # packet capture (live capture needs /dev/bpf perms, which is a permission thing, not a package thing)
    # Moved Xcode off masApps to xcodes (2026-08-02). mas's App Store delivery is a single
    # connection and can't be parallelized; xcodes + aria2 downloads the .xip in up to 16
    # parallel chunks (the .xip is a full ~7-10GB redownload every update, monthly-ish), and
    # xcodes gives explicit version control if a pinned build is ever needed. Latest-only for
    # now: `xcodes install --latest` from `just upgrade` keeps it current. Apple ID login is
    # required to download; credentials come from sops (xcodes/apple_id, xcodes/password) and
    # 2FA is prompted interactively on first auth / when the cached Apple session expires.
    # aria2 (which xcodes picks up from PATH) is declared in home/workstation.nix.
    xcodes # Xcode version manager (download/select/switch, replaces mas for Xcode)
    gnupg # GPG (git signing is SSH-based, so this is only for ad-hoc verify/decrypt)
  ];

  # Puddle: catalogs it may browse, sources it may install from, and the wallpapers this
  # machine should have. `puddle apply` reconciles the last of those.
  xdg.configFile."puddle/install.toml".source = ../../configs/puddle/install.toml;

  # The `puddle` CLI ships inside the app. Symlinked rather than copied so it follows updates.
  home.file.".local/bin/puddle".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/Puddle.app/Contents/Resources/puddle";

  home.file.".config/ghostty" = {
    source = ../../configs/terminals/ghostty;
    recursive = true;
  };
  # Ghostty: resolution-variable font size. Computes font-size from the main display's logical
  # vertical resolution and writes it to ~/.config/ghostty.local/font-size.conf (config includes it with ?).
  # Recomputed on every nh home switch. If you change resolution, switch again, or
  # run scripts/ghostty-fontsize.sh by hand → config reload in Ghostty to apply.
  home.activation.ghosttyFontSize = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.bash}/bin/bash ${../../scripts/ghostty-fontsize.sh}
  '';

  # lazygit: this Mac sets XDG_CONFIG_HOME=~/.config, so lazygit
  # prefers reading ~/.config/lazygit/config.yml. Meanwhile programs.lazygit on Darwin
  # writes to ~/Library/Application Support/lazygit/, so common.nix's theme settings
  # aren't actually applied (the empty file on the ~/.config side takes precedence).
  # So also generate programs.lazygit.settings at the XDG path to make it reliably effective.
  # (This definition is Darwin-only. On Linux, HM's lazygit module itself defines the same path,
  #  so putting it in common.nix would conflict.)
  xdg.configFile."lazygit/config.yml".source =
    (pkgs.formats.yaml { }).generate "lazygit-config.yml"
      config.programs.lazygit.settings;

  # MechvibesDX at login, in place of a System Settings login item. Lives here
  # rather than in darwin-services.nix because it needs the package path from
  # the let block above.
  #
  # Started through the bundle's executable, not $out/bin, so macOS still sees a
  # real .app - the tray icon and the Accessibility entry both depend on that.
  # --minimized keeps it in the tray at login: the config-driven start_minimized
  # only applies when auto_start is set, which is the Windows registry path.
  launchd.agents.mechvibes-dx = {
    enable = true;
    config = {
      ProgramArguments = [
        "${mechvibes-dx}/Applications/MechvibesDX.app/Contents/MacOS/mechvibes-dx"
        "--minimized"
      ];
      RunAtLoad = true;
      # No KeepAlive on purpose: quitting from the tray should stay quit, and a
      # crash loop on an app this experimental would be worse than silence.
      ProcessType = "Interactive"; # keystroke->sound latency, same as mopidy's agent
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/MechvibesDX/mechvibes-dx.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/MechvibesDX/mechvibes-dx.log";
    };
  };

  home.activation.mechvibesLogDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p "${config.home.homeDirectory}/Library/Logs/MechvibesDX"
  '';
}
