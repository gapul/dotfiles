{
  config,
  lib,
  pkgs,
  ...
}:
# Day and night appearance on nixos-laptop (2026-10-11): light while the sun is up, dark after
# sunset. darkman computes the two moments from a fixed position (Tokyo, city precision; no
# geoclue, nothing leaves the machine) and runs the scripts below at each transition.
#
# What follows the switch is the desktop-wide color-scheme the xdg portal serves from dconf
# (org.freedesktop.appearance color-scheme, via xdg-desktop-portal-gtk): Firefox
# (browser.theme.* = 2 in modules/home/firefox.nix), ghostty (theme = light:…,dark:…),
# libadwaita/GTK4 and Electron apps. waybar-appearance.nix and desktop-appearance.nix
# also switch the bar, Hyprland borders, notifications, lock screen, menus, and GTK/Qt
# palettes. Application-specific themes such as nvim remain independently configured.
#
# home/stylix.nix used to pin the same dconf key from the palette's `variant`; that line is
# gone, because two writers for one key means the rebuild undoes the sun. The oneshot below
# re-applies the current mode after every switch, which also covers the one activation
# where home-manager resets the key it no longer manages.
let
  palettes = (builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json)).palettes;
  wallpaperFor =
    name:
    import ../lib/wallpaper.nix {
      inherit pkgs name;
      p = palettes.${name};
    };
  lightWallpaper = wallpaperFor "rose-pine-dawn";
  darkWallpaper = wallpaperFor "rose-pine";
  # awww (the renamed swww) paints the wallpaper and can cross-fade to the other one, which
  # is what makes the sunrise/sunset switch a transition rather than a cut.
  awww = "${pkgs.awww}/bin/awww";
  setWallpaper = pkgs.writeShellScript "wallpaper-set" ''
    set -eu
    mode=''${1:-$(${pkgs.darkman}/bin/darkman get 2>/dev/null || echo dark)}
    case "$mode" in
      light) image=${lightWallpaper} ;;
      *) image=${darkWallpaper} ;;
    esac
    # Wait for the daemon's socket (this also runs right after the daemon starts).
    for _ in $(seq 1 50); do ${awww} query >/dev/null 2>&1 && break; sleep 0.1; done
    exec ${awww} img "$image" --transition-type fade --transition-duration 2 --transition-fps 60
  '';
  apply = pkgs.writeShellScript "appearance-apply" ''
    set -eu
    case "''${1:-}" in
      light) scheme=prefer-light ;;
      dark) scheme=prefer-dark ;;
      *) echo "usage: appearance-apply light|dark" >&2; exit 2 ;;
    esac
    # dconf directly rather than gsettings: no schema lookup, and it is what the portal watches.
    ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'$scheme'"
    ${setWallpaper} "$1" || true
  '';
in
{
  # The wallpaper daemon; the image for the current mode is set as soon as it is up.
  systemd.user.services.awww = {
    Unit = {
      Description = "awww wallpaper daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.awww}/bin/awww-daemon";
      ExecStartPost = "${setWallpaper}";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  services.darkman = {
    enable = true;
    settings = {
      lat = 35.68;
      lng = 139.77;
      usegeoclue = false;
      dbusserver = true; # `darkman get|set` and the nl.whynothugo.darkman D-Bus API
      portal = false; # the GTK portal already serves color-scheme from dconf; one server is enough
    };
    lightModeScripts.appearance = "${apply} light";
    darkModeScripts.appearance = "${apply} dark";
  };

  systemd.user.services.darkman-apply = {
    Unit = {
      Description = "Re-apply the current darkman mode to the portal color-scheme";
      After = [ "darkman.service" ];
      Requires = [ "darkman.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      # darkman needs a moment after start before `get` answers over D-Bus.
      ExecStart = "${pkgs.writeShellScript "darkman-apply" ''
        set -eu
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          if mode=$(${pkgs.darkman}/bin/darkman get 2>/dev/null) && [ -n "$mode" ]; then
            exec ${apply} "$mode"
          fi
          sleep 1
        done
        echo "darkman did not answer" >&2
        exit 1
      ''}";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
