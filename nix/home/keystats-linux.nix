{ pkgs, ... }:
let
  keystats = pkgs.callPackage ../pkgs/keystats-linux/package.nix { };
in
{
  home.packages = [ keystats ];
  systemd.user.services.keystats = {
    Unit = {
      Description = "KeyStats native keyboard statistics";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${keystats}/bin/keystats daemon";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
      Nice = 10;
      NoNewPrivileges = true;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
