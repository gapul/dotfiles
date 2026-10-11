{ pkgs, ... }:
let
  # Source of truth is gapul/keystats (linux/), checked out via ghq; this only pins a rev.
  # Bump rev + hash together when the Linux port changes.
  src = pkgs.fetchFromGitHub {
    owner = "gapul";
    repo = "keystats";
    rev = "5e307f5bc0ca96d9875c2840abe9f53e39967dd1";
    hash = "sha256-cnQjekEUapdi18BOBSYd7/Eaid7wT5sq11dK9LSNbeg=";
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
