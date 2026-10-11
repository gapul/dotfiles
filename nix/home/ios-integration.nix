{ pkgs, ... }:
let
  uxplay = pkgs.uxplay.overrideAttrs (old: {
    # PIN pairing uses SRP_SHA1 (20 bytes), not the 64-byte buffer capacity.
    # Keep the exact-length check and bound both client and server proof copies.
    postPatch = (old.postPatch or "") + ''
      substituteInPlace lib/raop_handlers.h \
        --replace-fail 'unsigned char proof[64]' 'unsigned char proof[20]'
    '';
  });
in
{
  # AirPlay requires Avahi publishing and Wi-Fi ports 7000..7002 on the host.
  systemd.user.services.uxplay = {
    Unit = {
      Description = "iPhone AirPlay receiver";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStartPre = pkgs.writeShellScript "wait-for-avahi" ''
        for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
          state=$(${pkgs.systemd}/bin/busctl --system call org.freedesktop.Avahi / org.freedesktop.Avahi.Server GetState 2>/dev/null || true)
          if [ "$state" = "i 2" ]; then exit 0; fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "Avahi did not reach running state" >&2
        exit 1
      '';
      ExecStart = "${pkgs.coreutils}/bin/stdbuf -oL -eL ${uxplay}/bin/uxplay -n nixlaptop -p 7000 -pin";
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
  systemd.user.services.syncclipboard = {
    Unit = {
      Description = "SyncClipboard desktop synchronization";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.callPackage ../pkgs/syncclipboard.nix { }}/bin/syncclipboard";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
