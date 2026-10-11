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
# libadwaita/GTK4 and Electron apps. The hand-themed parts of the rice (waybar, the
# Hyprland borders, mako, hyprlock, wofi, nvim) and stylix's GTK3/Qt colours are generated
# once from palettes.json and stay on the active palette; they are not switched here.
#
# home/stylix.nix used to pin the same dconf key from the palette's `variant`; that line is
# gone, because two writers for one key means the rebuild undoes the sun. The oneshot below
# re-applies the current mode after every switch, which also covers the one activation
# where home-manager resets the key it no longer manages.
let
  palettes = (builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json)).palettes;
  wallpaperConfig =
    mode: name:
    let
      image = import ../lib/wallpaper.nix {
        inherit pkgs name;
        p = palettes.${name};
      };
    in
    pkgs.writeText "hyprpaper-${mode}.conf" "wallpaper {\n  monitor=\n  path=${image}\n}\nsplash=false\n";
  lightWallpaper = wallpaperConfig "light" "rose-pine-dawn";
  darkWallpaper = wallpaperConfig "dark" "rose-pine";
  wallpaperStart = pkgs.writeShellScript "hyprpaper-appearance" ''
    set -eu
    # Query on every start so login, service restarts and new monitors use the current mode.
    mode=$(${pkgs.darkman}/bin/darkman get 2>/dev/null) || mode=dark
    case "$mode" in
      light) wallpaper=${lightWallpaper} ;;
      *) wallpaper=${darkWallpaper} ;;
    esac
    exec ${config.services.hyprpaper.package}/bin/hyprpaper --config "$wallpaper"
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
    # Do not block darkman's hook: hyprpaper queries darkman over D-Bus when starting.
    ${pkgs.systemd}/bin/systemctl --user --no-block try-restart hyprpaper.service
  '';
in
{
  # Own the launch config instead of Stylix's single, build-time wallpaper.
  systemd.user.services.hyprpaper.Service.ExecStart = lib.mkForce "${wallpaperStart}";

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
