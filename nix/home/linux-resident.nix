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
    # The service only runs aw-server, so the Rust server alone is enough. The default
    # pkgs.activitywatch also pulls in aw-qt and the Python aw-core, whose `peewee==3.*` pin
    # breaks the build whenever nixpkgs moves peewee ahead (4.4.0 on 2026-10-20).
    package = pkgs.aw-server-rust;
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
  # LibrePods 0.2.5 does try to pull the AirPods back when media starts playing here, but it
  # takes the address from the *currently connected* device and clears it on disconnect, so the
  # attempt is `bluetoothctl connect ""` and never succeeds. This watches the same MPRIS signal
  # and connects by address. The other direction (back to the iPhone) stays manual: Apple's
  # automatic switching is an iCloud conversation between Apple devices that Linux cannot join.
  systemd.user.services.airpods-autoconnect =
    let
      airpodsMac = "BC:80:4E:D3:47:18"; # 結己’s AirPods Pro
      script = pkgs.writeShellApplication {
        name = "airpods-autoconnect";
        runtimeInputs = [
          pkgs.playerctl
          pkgs.bluez
          pkgs.coreutils
          pkgs.gnugrep
        ];
        text = ''
          mac=${airpodsMac}
          last=0
          playerctl -a --follow status 2>/dev/null | while read -r st; do
            [ "$st" = "Playing" ] || continue
            bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes" && continue
            now=$(date +%s)
            # One attempt per 20 s: --follow fires on every player, and a connect takes a while.
            [ $((now - last)) -lt 20 ] && continue
            last=$now
            echo "media playing and AirPods disconnected; connecting $mac"
            if timeout 25 bluetoothctl connect "$mac" 2>&1 | grep -q "Connection successful"; then
              echo "connected"
            else
              echo "connect failed (AirPods asleep, in the case, or held by another device)"
            fi
          done
        '';
      };
    in
    {
      Unit = {
        Description = "Auto-connect AirPods when media starts playing";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.getExe script;
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

  xdg.configFile."espanso/config/default.yml".text = ''
    keyboard_layout:
      layout: us
  '';
  xdg.configFile."espanso/match/base.yml".source = ../../configs/espanso/base.yml;
  home.packages = [ (pkgs.callPackage ../pkgs/mechvibes-dx-linux.nix { }) ];
}
