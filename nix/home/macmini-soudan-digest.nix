{
  config,
  lib,
  pkgs,
  ...
}:
# gapul's half of the soudan bot's weekly progress slides (configs/macmini/hermes/README.md).
#
# The slides are written from the IS-CPU-6 org's activity, and its repos are mostly private.
# gapul's gh login can read them; the bot (hermes, and its hsoudan sandbox that strangers drive)
# must not hold that token. So gapul writes a plain digest — commit subjects, PR and issue
# titles — and the bot's cron pre-run script reads only that file. hermes reaches it because
# macOS puts every uid >= 500 in staff and ~ is 750 (see the hsoudan note in hosts/macmini.nix).
let
  home = config.home.homeDirectory;
  out = "${home}/.local/state/soudan-feed/github.md";
  digest = pkgs.writeShellApplication {
    name = "soudan-github-digest";
    bashOptions = [
      "errexit"
      "nounset"
    ];
    text = ''
      /bin/mkdir -p "$(dirname "${out}")"
      export PATH=${pkgs.gh}/bin:/usr/bin:/bin
      exec ${pkgs.python3}/bin/python3 ${../../configs/macmini/hermes/soudan-github-digest.py} "${out}" 8
    '';
  };
  # The other direction: the finished draft goes into IS-CPU-6/slides. The org has deploy keys
  # disabled, so this too is gapul's gh rather than a key the bot could hold.
  publish = pkgs.writeShellApplication {
    name = "soudan-slides-publish";
    bashOptions = [ ];
    text = ''
      export PATH=${pkgs.gh}/bin:${pkgs.git}/bin:${pkgs.poppler-utils}/bin:/usr/bin:/bin
      exec ${pkgs.python3}/bin/python3 ${../../configs/macmini/hermes/soudan-slides-publish.py} "$@"
    '';
  };
in
{
  launchd.agents.soudan-github-digest = {
    enable = true;
    config = {
      ProgramArguments = [ (lib.getExe digest) ];
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

  launchd.agents.soudan-slides-publish = {
    enable = true;
    config = {
      ProgramArguments = [ (lib.getExe publish) ];
      # The bot's job starts Monday 21:00 and takes a few minutes; try twice that evening.
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 21;
          Minute = 45;
        }
      ];
      RunAtLoad = false;
      ProcessType = "Background";
      StandardErrorPath = "${home}/Library/Logs/soudan-slides-publish.log";
      StandardOutPath = "${home}/Library/Logs/soudan-slides-publish.log";
    };
  };
  launchd.agents.soudan-slides-publish-final = {
    enable = true;
    config = {
      ProgramArguments = [
        (lib.getExe publish)
        "--final"
      ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 23;
          Minute = 15;
        }
      ];
      RunAtLoad = false;
      ProcessType = "Background";
      StandardErrorPath = "${home}/Library/Logs/soudan-slides-publish.log";
      StandardOutPath = "${home}/Library/Logs/soudan-slides-publish.log";
    };
  };
}
