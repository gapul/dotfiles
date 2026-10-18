{ config, pkgs, ... }:
{
  # SSH aliases and keys remain owned by sops; retry while the network is unavailable.
  # User units cannot order themselves after the system tailscaled.service.
  systemd.user.services.avatar-viewer-tunnel = {
    Unit = {
      Description = "SSH tunnel to avatar viewers via homeserver";
      StartLimitIntervalSec = 0;
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.openssh}/bin/ssh -N -o ControlMaster=no -o ControlPath=none -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ConnectTimeout=20 -L 127.0.0.1:8767:127.0.0.1:8767 -L 127.0.0.1:8877:127.0.0.1:8877 mvrx-dev";
      Restart = "always";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Keep the existing command/path; pin the viewer to the flake instead of nix run.
  # The VNC password is machine-local secret state and must not enter the store.
  home.file.".local/bin/vnc-macmini".source = pkgs.writeShellScript "vnc-macmini" ''
    set -eu
    password_file="${config.home.homeDirectory}/.vnc/macmini.passwd"
    if [ ! -r "$password_file" ]; then
      echo "VNC password file missing: $password_file" >&2
      exit 1
    fi
    exec ${pkgs.tigervnc}/bin/vncviewer -passwd "$password_file" 100.105.135.49 "$@"
  '';
}
