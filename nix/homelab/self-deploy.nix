# homeserver fetches main itself and switches to it.
#
# The reason for dropping the push direction is on the credentials side. Pushing from the
# main Mac makes that path depend on the main Mac's ssh key. Since the everyday key moved
# to the Secure Enclave it requires Touch ID approval and can't sign while unattended (it
# actually stopped on 2026-08-30 when the window expired). Rather than work around it by
# adding keys, use a shape where the pushing side needs no credentials.
#
# homeserver only reads a public flake, so nobody's key is needed. Merged config gets
# applied even if the main Mac is broken or away.
{ pkgs, ... }:
{
  systemd.services.self-deploy = {
    description = "main が進んでいたら自分で切り替える";
    # Don't let it restart itself. switch-to-configuration restarts units whose definition
    # changed, so if this unit itself were a target it would be killed mid-switch.
    # (nixos-rebuild moves the switch itself into a separate unit via systemd-run, but
    #  being a restart target is a separate matter.)
    restartIfChanged = false;
    path = with pkgs; [
      git
      nixos-rebuild
      nix
      curl
      coreutils
      gawk
      systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/self-deploy.sh}";
      # Only root can switch.
      User = "root";
      StateDirectory = "self-deploy";
    };
  };

  systemd.timers.self-deploy = {
    description = "自動更新を 1 時間おきに走らせる";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15min";
      OnUnitActiveSec = "1h";
      Persistent = true;
      # Don't hit GitHub exactly on the hour.
      RandomizedDelaySec = "10min";
    };
  };
}
