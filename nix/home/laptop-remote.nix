{ pkgs, ... }:
{
  # SSH aliases and keys remain owned by sops; retry while the network is unavailable.
  # User units cannot order themselves after the system tailscaled.service.
  # Replaces the hand-written ~/.config/systemd/user/avatar-viewer-tunnel.service (same command).
  # vnc-macmini, which this file also used to carry, lives in home/linux-gui.nix.
  systemd.user.services.avatar-viewer-tunnel = {
    Unit = {
      Description = "SSH tunnel to avatar viewers via homeserver";
      StartLimitIntervalSec = 0;
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.openssh}/bin/ssh -N -o ControlMaster=no -o ControlPath=none -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ConnectTimeout=20 -L 127.0.0.1:8767:127.0.0.1:8767 -L 127.0.0.1:8877:127.0.0.1:8877 sean-dev";
      Restart = "always";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
