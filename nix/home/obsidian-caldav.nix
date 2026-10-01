# Two-way sync between Obsidian checkbox tasks and the Radicale task lists (dav.gapul.net).
# The code is personal-tools/obsidian-caldav (private repo); see its docstring for the rules.
#
# It runs here because this is the only machine with the vault as plain files: the homeserver's
# copy is a receive-only Syncthing mirror, and CouchDB holds it end-to-end encrypted. The Mac
# sleeping only delays a round; the next one picks up whatever both sides changed meanwhile.
# Radicale credentials come from sops (radicale/username, radicale/password in home/secrets.nix).
{ pkgs, ... }:

{
  launchd.agents.obsidian-caldav = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "obsidian-caldav" ''
          src="$HOME/Developer/github.com/gapul/personal-tools/obsidian-caldav/sync.py"
          [ -f "$src" ] || exit 0
          exec ${pkgs.python3}/bin/python3 "$src"
        ''}"
      ];
      StartInterval = 600;
      RunAtLoad = true;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "/tmp/obsidian-caldav.log";
      StandardErrorPath = "/tmp/obsidian-caldav.log";
    };
  };
}
