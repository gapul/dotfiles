{
  config,
  pkgs,
  lib,
  ...
}:
# restic backup for macmini. Uses the same shared library as the main Mac's restic-backup.nix.
#
# Originally this was ~/.local/bin/restic-macmini-offsite.sh plus a hand-written plist, and
# it only covered ~/Developer. Being outside the declarations was one thing, but the real
# damage was that ~/.config (Claude history and more) and ~/ai were never protected.
#
# Three differences from the main Mac:
#   - The sops entry point differs. On the main Mac home-manager opens it with the human's
#     age key; here the system-side sops in hosts/macmini.nix opens it with this machine's
#     SSH host key and puts it in the same place. The path stays the shared library's
#     default (= the original hand-placed location), so this file doesn't need to know
#     which one placed it.
#   - There is no screen, so no osascript; notifications go only to ntfy.
#   - It owns prune/check/freshness monitoring for the whole shared repository. The
#     control plane is concentrated on the always-on host, and the main Mac only sends
#     its own snapshots.
#
# Each data-holding host runs only its own backup. Only this Mac mini exclusively
# repacks/checks the shared repository, avoiding concurrent runs and laptop sleep.
let
  home = config.home.homeDirectory;
  common = import ../lib/restic-common.nix { inherit home; };

  # Use the shared library's default path as is. The system-side sops places the contents
  # (hosts/macmini.nix). It's the same place as when it was placed by hand, so nothing changes here.
  inherit (common) passwordFile;
  logFile = "${home}/Library/Logs/restic-backup.log";

  ntfyUrlFile = "${home}/.config/ntfy/url";
  ntfyTokenFile = "${home}/.config/ntfy/token";

  scripts = common.mkScripts {
    inherit
      pkgs
      lib
      passwordFile
      logFile
      ;
    backupPaths = [
      # The whole working tree. The only target the old script covered; documents that
      # were scattered directly under home have also been gathered under projects/
      # (~/Documents isn't used on this machine because macOS TCC refuses scans from ssh
      # and launchd).
      "${home}/Developer"
      # Minecraft worlds. The real data lives in mcsrv's home (unreadable from this agent),
      # so pick up what the 4:40 minecraft-backup packs up. This is the only offsite path.
      "/Users/Shared/minecraft-backups"
      # ~/ai was folded up on 2026-08-12. Leaving it as a path makes lstat fail and ntfy
      # fire every morning, so its contents were scattered per the declared layout.
      # manabi-dashboard was further split out as a service into gapul/manabi on
      # 2026-08-13 and is a clone at /Users/Shared/manabi on this machine; since it's in
      # git there's no need to pick it up here. The stopped mopidy-dev was moved to ~/tmp.
      # This was completely unprotected until now. It holds Claude Code history
      # (~/.config/claude) and each tool's state. Symlinks into the store aren't followed.
      "${home}/.config"
      # Hermes state. The dedicated user's home isn't readable from gapul (drwx------),
      # so it uses the same approach as Minecraft: a root daemon packs it up and puts it
      # here, and restic picks that up. The contents are state.db (525 Discord
      # conversations, including the full-text search index) and the .env set; neither
      # can be recreated. hermes-agent itself and node can be reinstalled, so not included.
      "/Users/Shared/hermes-backups"
      # Presenta database. pg_dumped at 4:30 by the daemon in hosts/macmini-presenta.nix.
      "/Users/Shared/presenta-backups"
      # Presenta slide images and videos. The store shared by every release (hosts/macmini-presenta.nix).
      "${home}/.local/share/presenta/data"
    ];
    extraExcludes = [
      "**/.DS_Store"
      # Re-downloadable weights and caches. .gguf files sometimes get put in ai/.
      "**/*.gguf"
      "**/*.safetensors"
      "**/*.bin"
      "**/models"
      # models alone doesn't catch GPT-SoVITS's pretrained_models. s2G488k.pth,
      # s1v3.ckpt, and bigvgan_generator.pt slipped through, and 4.3GiB of re-downloadable
      # distribution files went to Google Drive every day (measured 2026-08-12; this
      # brings it down to just under 100MB).
      "**/pretrained_models"
      "**/*.pth"
      "**/*.ckpt"
      "**/*.pt"
      "**/node_modules"
      "**/.venv"
      "**/.direnv"
      "**/target"
      "**/dist"
      "**/build"
      "**/.next"
      "**/.expo"
      "**/.git/objects"
      # Don't put the key that opens this repository inside this repository. Same policy
      # as stated at the top of the main Mac's module: the key lives in the password manager.
      "**/.config/restic"
      # Things Claude Code can put back. versions holds binaries of several hundred MB.
      "**/.config/claude/cache"
      "**/.config/claude/downloads"
      "**/.config/claude/versions"
    ];
    notifyBody = ''
      if [ -r "${ntfyUrlFile}" ] && [ -r "${ntfyTokenFile}" ]; then
        /usr/bin/curl -fsS --max-time 15 \
          -H "Authorization: Bearer $(cat "${ntfyTokenFile}")" \
          -H "Title: restic (macmini)" \
          -H "Priority: high" \
          -H "Tags: warning" \
          -d "$1: $2" \
          "$(cat "${ntfyUrlFile}")" >/dev/null 2>&1 || true
      fi'';
    # Read only YYYY-MM-DDTHH:MM:SS, regardless of whether fractional seconds are present.
    parseSnapshotTime = ''$(date -j -f "%Y-%m-%dT%H:%M:%S" "''${latest:0:19}" +%s 2>/dev/null || echo 0)'';
  };
in
{
  home.packages = [ pkgs.restic ];

  # 5:00, same as the old script. The main Mac runs at 13:00, so shared-repository locks don't overlap.
  launchd.agents = {
    # 5:00 backup, followed by the sole repository-wide retention/prune pass.
    restic-backup = import ../lib/launchd-agent.nix {
      program = "${scripts.backup}";
      schedule = [
        {
          Hour = 5;
          Minute = 0;
        }
      ];
      nice = 5;
      longRunning = true;
    };

    # Repository integrity belongs to the always-on control-plane host.
    restic-check = import ../lib/launchd-agent.nix {
      program = "${scripts.check}";
      schedule = [
        {
          Weekday = 0;
          Hour = 14;
          Minute = 0;
        }
      ];
      nice = 5;
      longRunning = true;
    };

    # One monitor checks freshness for every host in the shared repository.
    restic-monitor = import ../lib/launchd-agent.nix {
      program = "${scripts.monitor}";
      schedule = [
        {
          Hour = 19;
          Minute = 0;
        }
      ];
      nice = 5;
    };
  };
}
