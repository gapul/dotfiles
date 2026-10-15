{ pkgs, ... }:
let
  # Source of truth is gapul/keystats (linux/), checked out via ghq; this only pins a rev.
  # Bump rev + hash together when the Linux port changes.
  src = pkgs.fetchFromGitHub {
    owner = "gapul";
    repo = "keystats";
    rev = "e66ec1f9f0ed65283bf252a9cf60f07374f1b83a"; # niri support (gapul/keystats#2)
    hash = "sha256-yDs3DV7ER11uze1NzjzbtWyH3ilRSeXM8HumsvAVxQM=";
  };
  keystats = pkgs.callPackage "${src}/linux/package.nix" { };
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
