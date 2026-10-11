{ lib, pkgs, ... }:
{
  # One owner per daemon: disable upstream XDG autostart entries in favour of systemd.
  xdg.configFile."autostart/librepods.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=LibrePods
    Hidden=true
  '';
  xdg.configFile."autostart/librepods.desktop".force = true;
  xdg.configFile."autostart/org.kde.kdeconnect.daemon.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=KDE Connect
    Hidden=true
  '';
  services.kdeconnect.enable = true;
  services.activitywatch = {
    enable = true;
    watchers.aw-watcher-window-wayland.package = pkgs.aw-watcher-window-wayland;
  };
  # Window and AFK capture need a live Wayland session, not just a user login.
  systemd.user.targets.activitywatch = {
    Unit.After = [ "graphical-session.target" ];
    Unit.PartOf = [ "graphical-session.target" ];
    Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
  };
  systemd.user.services.activitywatch-watcher-aw-watcher-window-wayland.Service = {
    Restart = "on-failure";
    RestartSec = 5;
  };
  xdg.configFile."espanso/config/default.yml".text = ''
    keyboard_layout:
      layout: us
  '';
  xdg.configFile."espanso/match/base.yml".source = ../../configs/espanso/base.yml;
  home.packages = [ (pkgs.callPackage ../pkgs/mechvibes-dx-linux.nix { }) ];
}
