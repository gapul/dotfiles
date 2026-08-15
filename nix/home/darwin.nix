{
  config,
  pkgs,
  lib,
  user,
  nixpkgsUnstable,
  ...
}:
let
  # Bound here rather than inline in home.packages because the LaunchAgent below
  # needs the path too, and both must point at the same store path.
  mechvibes-dx = pkgs.callPackage ../pkgs/mechvibes-dx.nix { };

  # The bundle actually launched: a signed copy of the one in the store, see
  # home.activation.mechvibesSign below.
  mechvibesApp = "/Applications/MechvibesDX.app";
in
{
  imports = [
    ../modules/home/darwin-chrome.nix
    ../modules/home/darwin-services.nix
    ../modules/home/darwin-apps.nix
    ../modules/home/darwin-ai-client.nix
  ];

  # Nothing puts an .app under ~/Applications any more: bundles come from environment.systemPackages
  # (hosts/darwin.nix) into /Applications/Nix Apps, and the two written by hand - MechvibesDX's
  # signed copy and the mpv droplet - go straight to /Applications. Left enabled this would keep
  # generating an empty "Home Manager Apps" alongside them. mac-app-util's trampolines went with it
  # (the input is gone), since it existed only to make the ~/Applications symlinks indexable.
  #
  # The catch: a package added to home.packages that does ship an .app now lands nowhere visible,
  # silently. Put GUI packages in environment.systemPackages.
  targets.darwin.linkApps.enable = false;

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
    pngpaste # needed for macOS image paste in obsidian.nvim / img-clip
    syncthing # Syncthing CLI (the resident is the LaunchAgent in services.syncthing)
    xcodegen # generate .xcodeproj from project.yml (Mac-only, since meta.platforms = darwin in Linux nixpkgs)
    (callPackage ../pkgs/slk.nix { }) # Slack TUI (pinned to the official GitHub Release)
    # sketchybar's event helper. `sketchybarrc` used to compile it on every bar start from
    # sources kept in the config directory; the launchd agents put the profile first on PATH.
    (callPackage ../pkgs/sketchybar-helper { })
    # zrythm (DAW): broken=isDarwin in nixpkgs. Self-built for darwin with carla included.
    # See pkgs/zrythm-darwin/ for details. GUI must be launched in a foreground GUI session.
    # On 26.05-darwin appstream/libadwaita can't build on darwin, so this one package alone
    # uses nixos-unstable pkgs (nixpkgsUnstable, via commonSpecialArgs in flake.nix).
    (import ../pkgs/zrythm-darwin {
      pkgs = nixpkgsUnstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
    })
    # ardour / aseprite / fritzing / qview / vroid-studio used to sit here. They ship .app
    # bundles, and home-manager can only surface those under ~/Applications, so they moved to
    # environment.systemPackages in hosts/darwin.nix where nix-darwin puts them in
    # /Applications/Nix Apps. mechvibes-dx and zrythm stay: the former needs the per-user
    # signed copy below, the latter ships no bundle.

    # ─── CLI migrated from Homebrew (stage 4: mac CLI that had no reason to stay on brew) ───
    # All of these exist in nixpkgs for aarch64-darwin and substitute from the cache, and none of
    # them needs a brew service / tap / keg. See hosts/darwin.nix's brews for what stays on brew and why.
    sox # audio processing (rec / play / sox / soxi)
    # Talk to the iPhone over USB without Finder. Voice Memos keeps its recordings inside the app
    # sandbox, which AFC cannot reach, so the only way off the device is a device backup
    # (idevicebackup2) and pulling the AppDomainGroup-group.com.apple.VoiceMemos.shared files out
    # of its Manifest.db.
    libimobiledevice
    exiftool # strip metadata (GPS/device info) from images/PDFs before sharing
    blueutil # Bluetooth CLI
    duti # file associations
    scrcpy # Android screen mirroring
    android-tools # adb (droid command, mobile/android scripts)
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

  # OmniWM / CodexBar: both apps write their own config back on every UI change, so a store
  # symlink (read-only) breaks saving. Out-of-store symlinks instead — the app writes straight
  # into the repo, which replaces the old `just app-snapshot` one-way mirror (removed 2026-08-13).
  # CodexBar's config carries the Codex account UUID; this repo is public, but a bare account
  # identifier is not a credential, so it is tracked as-is.
  home.file.".config/omniwm/settings.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/wm/omniwm/settings.toml";
  home.file.".config/codexbar/config.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/apps/codexbar/config.json";
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
  # Started through the signed copy's executable, not $out/bin, so macOS still
  # sees a real .app - the tray icon and the Accessibility entry both depend on
  # that.
  # --minimized keeps it in the tray at login: the config-driven start_minimized
  # only applies when auto_start is set, which is the Windows registry path.
  launchd.agents.mechvibes-dx = {
    enable = true;
    config = {
      ProgramArguments = [
        "${mechvibesApp}/Contents/MacOS/mechvibes-dx"
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

  # TCC pins its rows to the code signature, and what nix builds is ad-hoc
  # signed: the requirement is a bare cdhash, so every rebuild of the package
  # silently revokes Accessibility and the app goes quiet (twice so far,
  # 2026-08-09 and 2026-08-13). Signing with the Developer ID that keystats
  # uses turns the requirement into a certificate check, which survives.
  #
  # codesign cannot write into the store, hence the copy. The copy still links its dylibs by
  # absolute store path, so the source has to stay alive: interpolating ${mechvibes-dx} into this
  # script puts it in the generation's references, which is what roots it. It is deliberately not
  # in home.packages - that would also link the bundle into ~/Applications/Home Manager Apps and
  # leave a second, unsigned MechvibesDX.app next to this one.
  #
  # Before setupLaunchAgents so the bundle exists when launchd is told to start
  # it. Deliberately not fatal: an unsignable bundle should cost the keystroke
  # sounds, not the whole activation.
  home.activation.mechvibesSign =
    lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
      ''
        src=${mechvibes-dx}/Applications/MechvibesDX.app
        stamp="${config.xdg.stateHome}/mechvibes-dx-store-path"
        if [ "$(cat "$stamp" 2>/dev/null)" != "$src" ] || ! /usr/bin/codesign -v "${mechvibesApp}" 2>/dev/null; then
          $DRY_RUN_CMD /bin/mkdir -p "${config.xdg.stateHome}"
          $DRY_RUN_CMD /bin/rm -rf "${mechvibesApp}" "$stamp"
          $DRY_RUN_CMD /bin/cp -R "$src" "${mechvibesApp}"
          $DRY_RUN_CMD /bin/chmod -R u+w "${mechvibesApp}"
          # No --options runtime: the hardened runtime blocks the WebView's JIT.
          if $DRY_RUN_CMD /usr/bin/codesign --force \
            --sign "Developer ID Application: Yuki Kawashima (S3H296G6Q5)" "${mechvibesApp}"; then
            $DRY_RUN_CMD echo "$src" > "$stamp"
          else
            echo "mechvibes-dx: codesign failed, Accessibility will need re-granting" >&2
          fi
        fi
      '';
}
