{ config, pkgs, ... }:
# GUI apps for the NixOS laptop. Imported only on nixos-laptop.
#
# The mac declares the same set as Homebrew casks (hosts/darwin.nix): on darwin nixpkgs GUI
# builds are unbundled and miss Spotlight / TCC / Launch Services, so casks win there. On
# Linux there is no such split, so the packages go straight into the closure and stay
# declarative.
#
# The browser is the exception to "just a package": Firefox Developer Edition is the daily
# driver on both machines and its profile/policies live in modules/home/firefox.nix (shared with
# the Mac), so it is wired through programs.firefox below instead of the list. It replaced Zen
# here on 2026-10-01; Zen's old profile (~/.zen) is left on disk for manual deletion.
let
  browser = "firefox-devedition.desktop"; # nixpkgs' wrapper names it after the binary
in
{
  imports = [ ../modules/home/firefox.nix ];

  # Always start on the declared profile. Developer Edition ignores profiles.ini's Default=1 and
  # creates a "dev-edition-default" profile of its own, which it then has to write into
  # profiles.ini; home-manager links that file read-only from the store, so the write fails and
  # Firefox stops at "Profile Missing" (2026-10-08, Firefox 156). The wrapper already sets
  # MOZ_LEGACY_PROFILES=1, which no longer prevents it. --profile skips the lookup entirely, and
  # links opened later still reach the running window because they name the same profile.
  # overrideAttrs keeps .override working, which home-manager uses to inject the policies.
  programs.firefox.package = pkgs.firefox-devedition.overrideAttrs (old: {
    makeWrapperArgs = old.makeWrapperArgs ++ [
      "--add-flags"
      "--profile ${config.home.homeDirectory}/${config.programs.firefox.profilesPath}/dev"
    ];
  });

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = browser;
      "application/xhtml+xml" = browser;
      "x-scheme-handler/http" = browser;
      "x-scheme-handler/https" = browser;
      "x-scheme-handler/about" = browser;
      "x-scheme-handler/unknown" = browser;
      # claude-cli:// deep links. Claude Code writes this association (and its own .desktop
      # under ~/.local/share/applications) into an unmanaged mimeapps.list on its own; once
      # the file became home-manager's, that copy blocked activation ("would be clobbered")
      # and replacing it would have dropped the handler, so it is declared here instead.
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };
  };
  # Claude Code re-registers its handler with a plain write, which can turn the symlink back
  # into a regular file and fail the next rebuild the same way. Everything it writes is
  # declared above, so overwriting that copy loses nothing.
  xdg.configFile."mimeapps.list".force = true;

  home.packages = with pkgs; [
    # ─── Browsers ───
    google-chrome # for sites that only test against Chrome, and for the automation profile
    tor-browser

    # ─── Passwords / 2FA ───
    bitwarden-desktop # the vault the SSH agent policy is built around
    keepassxc # offline vault (the same kdbx the iOS KeePassium build reads)

    # ─── Notes / Documents ───
    obsidian # vault syncs over the self-hosted CouchDB LiveSync
    thunderbird

    # ─── Messaging ───
    beeper
    simplex-chat-desktop

    # ─── Devices / Remote ───
    localsend # AirDrop-shaped transfer to the phone
    kdePackages.kdeconnect-kde
    rustdesk
    deskflow # share one keyboard/mouse across machines

    # ─── Network ───
    mullvad-vpn

    # ─── Creative / CAD / DTM ───
    blender
    freecad
    bitwig-studio # the one DAW, per the "Bitwig only" decision
    orca-slicer # Bambu A1 mini, same profile set as the mac

    # ─── Utilities ───
    imhex # hex editor
    espanso # text expansion (Wayland support is partial; see note below)

    # ─── Wayland extras that have no macOS counterpart ───
    swappy # annotate what hyprshot captured
    wl-mirror # mirror a region into a window (for screen sharing a slice)

    # ─── Non-Steam game launchers ───
    # Steam itself is system-side (programs.steam in hosts/nixos-laptop.nix) because it
    # needs the 32-bit graphics stack. These two only manage their own prefixes.
    lutris # GOG / standalone installers / emulators
    heroic # Epic / GOG / Amazon — the libraries the homelab free-games claimer fills up
  ];

  # espanso on Wayland needs the wayland variant and does not work under every compositor.
  # Left as a plain package rather than a service for now: enabling it as a systemd user
  # service before confirming it can inject into Hyprland windows would just add a failing
  # unit to `systemctl --user --failed`.
}
