# Pulls the lifelog notes that macmini writes (home/macmini-lifelog.nix) into the vault's
# 06_lifelog/. This is the only machine with the vault as plain files; from here LiveSync takes
# them to the phone and the hourly vault-git commit on homeserver picks them up.
#
# The notes are machine-owned: an edit made to one in Obsidian is overwritten the next time
# macmini rewrites that day. Write your own words in the diary instead.
{ config, pkgs, ... }:

let
  home = config.home.homeDirectory;
in
{
  launchd.agents.lifelog-pull = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "lifelog-pull" ''
          vault="${home}/Documents/notes"
          [ -d "$vault" ] || exit 0
          # id_automation, not the Enclave key: no Touch ID for an unattended job, and no agent
          # (a hung ssh-agent freezes every ssh). No forwards: the macmini Host block has some.
          exec ${pkgs.rsync}/bin/rsync -a --exclude='*.tmp' \
            -e "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none -o ClearAllForwardings=yes -i ${home}/.ssh/id_automation" \
            macmini:.local/share/lifelog/ "$vault/06_lifelog/"
        ''}"
      ];
      StartInterval = 900;
      RunAtLoad = true;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "/tmp/lifelog-pull.log";
      StandardErrorPath = "/tmp/lifelog-pull.log";
    };
  };
}
