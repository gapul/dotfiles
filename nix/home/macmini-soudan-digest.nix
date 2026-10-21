{ config, pkgs, ... }:
# GitHub half of the soudan bot's weekly progress slides (configs/macmini/hermes/README.md).
#
# The slides are written from the IS-CPU-6 org's activity, and its repos are mostly private.
# gapul's gh login can read them; the bot (hermes, and its hsoudan sandbox that strangers drive)
# must not hold that token. So gapul writes a plain digest — commit subjects, PR and issue
# titles — and the bot's cron pre-run script reads only that file. hermes reaches it because
# macOS puts every uid >= 500 in staff and ~ is 750 (see the hsoudan note in hosts/macmini.nix).
let
  home = config.home.homeDirectory;
  out = "${home}/.local/state/soudan-feed/github.md";
  digest = pkgs.writeShellScript "soudan-github-digest" ''
    set -eu
    /bin/mkdir -p "$(dirname "${out}")"
    export PATH=${pkgs.gh}/bin:/usr/bin:/bin
    exec ${pkgs.python3}/bin/python3 ${../../configs/macmini/hermes/soudan-github-digest.py} "${out}" 8
  '';
in
{
  launchd.agents.soudan-github-digest = {
    enable = true;
    config = {
      ProgramArguments = [ "${digest}" ];
      # Daily, so a broken login shows up long before Monday; the slides job runs Monday 21:00.
      StartCalendarInterval = [
        {
          Hour = 20;
          Minute = 30;
        }
      ];
      RunAtLoad = false;
      ProcessType = "Background";
      StandardErrorPath = "${home}/Library/Logs/soudan-github-digest.log";
      StandardOutPath = "${home}/Library/Logs/soudan-github-digest.log";
    };
  };
}
