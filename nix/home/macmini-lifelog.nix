{ config, pkgs, ... }:
# Writes the daily lifelog notes (timeline + facts + summary) for the Obsidian vault. The code
# is personal-tools/lifelog (private repo); its docstring lists the sources and the rules.
#
# Why here: it reads from all over (Dawarich, GitHub, the main Mac's personal-history snapshot
# on homeserver, the ledger on homeserver, Claude/Codex history from ai-agent-state) and the
# summary is written by agy, which is signed in on this always-on machine. The vault itself is
# plain files only on the main Mac, so that side pulls the output (home/lifelog-pull.nix).
#
# Not in sops: ~/.config/lifelog/dawarich.token (the Dawarich API key, placed by hand like the
# geekfeed tokens). Without it the location section reports itself as missing; the rest works.
let
  home = config.home.homeDirectory;
  tools = "${home}/Developer/github.com/gapul/personal-tools";

  run = pkgs.writeShellScript "lifelog" ''
    set -u
    # launchd passes no LANG; Python then writes the Japanese note fine but git/gh messages
    # and anything a shell interpolates next to multibyte text go wrong.
    export LANG=en_US.UTF-8
    export PATH="${pkgs.gh}/bin:${pkgs.rsync}/bin:${pkgs.git}/bin:/usr/bin:/bin"
    # https remote and no terminal: never wait on a credential prompt. A stale clone only means
    # an older script, so a failed pull is not fatal.
    GIT_TERMINAL_PROMPT=0 git -C "${tools}" pull -q --ff-only >/dev/null 2>&1 || true
    [ -f "${tools}/lifelog/lifelog.py" ] || exit 0
    exec ${pkgs.python3}/bin/python3 "${tools}/lifelog/lifelog.py"
  '';
in
{
  launchd.agents.lifelog = {
    enable = true;
    config = {
      ProgramArguments = [ "${run}" ];
      # Today's note grows through the day; yesterday's settles once the main Mac's snapshot
      # (04:20 or on wake) arrives. Unchanged days cost a few API calls and no summary.
      StartInterval = 3600;
      RunAtLoad = true;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "${home}/Library/Logs/lifelog.log";
      StandardErrorPath = "${home}/Library/Logs/lifelog.log";
    };
  };
}
