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
  # The target's ordering does not carry over to the services it pulls in, so the watcher itself
  # waits for the session too. Under niri it still started before WAYLAND_DISPLAY reached the
  # user manager, panicked, and hit the start limit; with no limit it retries until it connects.
  systemd.user.services.activitywatch-watcher-aw-watcher-window-wayland = {
    Unit = {
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      StartLimitIntervalSec = 0;
    };
    Service = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  xdg.configFile."espanso/config/default.yml".text = ''
    keyboard_layout:
      layout: us
  '';
  xdg.configFile."espanso/match/base.yml".source = ../../configs/espanso/base.yml;
  home.packages = [ (pkgs.callPackage ../pkgs/mechvibes-dx-linux.nix { }) ];
}
