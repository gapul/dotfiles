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
in
{
  imports = [
    ../modules/home/darwin-chrome.nix
    ../modules/home/darwin-services.nix
    ../modules/home/darwin-apps.nix
  ];

  # macOS-specific home-manager config
  # Common parts are split into home/common.nix

  home.homeDirectory = "/Users/${user.username}";

  home.sessionVariables = {
    HOMEBREW_NO_ANALYTICS = "1";
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

  # Append Mac-specific zsh init (added after common's initContent)
  programs.zsh.initContent = lib.mkAfter ''
    if [[ -f /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

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
          sudo pmset -a disablesleep 0 && echo "スリープ無効を解除しました (通常のスリープに戻ります)"
          ;;
        status|"")
          if pmset -g | grep -q "SleepDisabled.*1"; then
            echo "現在: スリープ無効 (フタを閉じても動作継続)"
          else
            echo "現在: 通常 (フタを閉じるとスリープ)"
          fi
          ;;
        on)
          sudo pmset -a disablesleep 1 && echo "スリープを無効化しました (フタを閉じても動作継続 / 電源接続を推奨)"
          ;;
        *)
          echo "使い方: nosleep [on|off|status]"
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
  ];

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
}
