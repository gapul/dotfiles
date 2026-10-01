{
  config,
  pkgs,
  lib,
  ...
}:
# Encrypted backup + integrity check + run monitoring via restic, scheduled by launchd (macOS only).
# Backend is the existing rclone google-drive remote (rclone_conf from [[project_xdg_migration]]).
#
# Division of responsibility:
#   - system/app/config are reproducible via nix+dotfiles (no backup needed)
#   - what we protect here is only the "non-reproducible user data"
#
# Prerequisites (if unmet, backup just skips harmlessly):
#   1. Re-auth rclone google-drive: (`rclone authorize "drive"` → put the token into sops's rclone_conf)
#   2. The repository is auto-init'd on the first success
#
# Note (circular dependency): the restic passphrase, age key, and ssh key are "the keys to this repo itself",
#   so they're not protected by restic. Always store them separately in a password manager (Bitwarden/Ente).
let
  home = config.home.homeDirectory;

  # SSO: repository / retention policy / archive tag / rclone conf live in nix/lib/restic-common.nix.
  #   The linux version (restic-backup-linux.nix) and the Justfile pull the same values. To avoid breaking the shared repo.
  common = import ../lib/restic-common.nix { inherit home; };

  passwordFile = config.sops.secrets."restic_password".path;
  logFile = "${home}/Library/Logs/restic-backup.log";

  # ntfy failure notification (homelab's ntfy.gapul.net). The URL (topic included) and token are sops-managed.
  #   If they're unexpanded/unreadable, notify quietly falls back to osascript only.
  ntfyUrlFile = config.sops.secrets."unified_calendar/ntfy_url".path;
  ntfyTokenFile = config.sops.secrets."unified_calendar/ntfy_token".path;

  # The scripts live in lib/restic-common.nix (shared with the linux version).  This
  # workstation only creates its own snapshots now.  Repository-wide prune/check/monitor
  # are control-plane work and run on the always-on Mac mini (macmini-backup.nix).
  # A stable location so the TCC grant sticks. See the activation below for why.
  tccBinDir = "${home}/.local/libexec/tcc";

  scripts = common.mkScripts {
    inherit
      pkgs
      lib
      passwordFile
      logFile
      ;
    pathPrefix = tccBinDir;
    # Apply retention to this host's snapshot metadata, but leave the expensive
    # repository-wide repack to the Mac mini.
    forgetSnippet = common.forgetOwnHostOnly;
    backupPaths = [
      "${home}/Documents"
      "${home}/Pictures"
      "${home}/Downloads"
      "${home}/Movies"
      "${home}/Music"
      # Only the Syncthing share, never ~/Sync itself: its siblings are rclone mounts of Google
      # Drive, and the restic repository lives on that same Drive, so backing up the mount would
      # feed the repository into itself.
      "${home}/Sync/syncthing" # Syncthing share (local-primary replicated data)
      # No official-launcher data any more: the launcher itself was gone and its two throwaway
      # single-player worlds were archived (restic --tag archive, snapshot 7e944f25, 2026-09-26)
      # and deleted. The worlds that matter live on the macmini (/Users/mcsrv/*, tarred into
      # /Users/Shared/minecraft-backups and picked up by home/macmini-backup.nix). Listing a
      # missing path here would make every daily run exit non-zero and page ntfy.
      # PrismLauncher instances. Most of the content is mod setups, not worlds: of 38MB, modded
      # takes 26MB. Individual mods can be re-downloaded, but reproducing "which ones, at which
      # versions" takes effort, so they are taken along with the worlds. The launcher's
      # assets/libraries/java (1.6GB total) are not included — those are refetched on launch.
      "${home}/Library/Application Support/PrismLauncher/instances"
      # Steam saves. Most live in Steam Cloud; only 192KB remains locally.
      # It costs no space, so keep it for titles that are not cloud-synced.
      "${home}/Library/Application Support/Steam/userdata"
      "${home}/Desktop" # small, but the only home dir that was silently outside the set
      # Voice Memos used to be listed here, back when the group container was the only copy.
      # The recordings were transcribed, renamed and moved to Drive
      # (05_録音・動画/VoiceMemos_archive, 259 files) and deleted from both the Mac and the
      # phone, so the container now holds 3.3MB of app scaffolding and zero .m4a. Keeping the
      # path only produced a daily "operation not permitted" — launchd's restic has no Full
      # Disk Access, so it could never read the container anyway — which made every run exit 3
      # and the run-freshness monitor useless. Restore from Drive if recordings ever come back.
      "${home}/.local/share/keystats" # keystats time series (a re-run cannot recreate it)
      # ActivityWatch, same class as keystats: 8 months and 1.1M events of what was on screen,
      # recorded once and never recomputable. aw-server-rust keeps it in one SQLite file.
      # aw-server is the pre-0.14 Python server's DB: fully imported into the Rust one, kept as
      # the untouched original (unchanged, so restic dedups it to nothing).
      "${home}/Library/Application Support/activitywatch/aw-server-rust"
      "${home}/Library/Application Support/activitywatch/aw-server"
      # Firefox Developer Edition's profile (the daily browser since 2026-09-26). Bookmarks already
      # ride floccus, so what is at stake here is the history and the per-extension settings; the
      # caches under it are excluded below. Zen's profile left the set when Zen was removed
      # (2026-10-01); its history stays in the older snapshots.
      "${home}/Library/Application Support/Firefox/Profiles"
    ];
    extraExcludes = [
      "**/.DS_Store"
      "**/*.photoslibrary"
      "**/ae-mcp-commands"
      # The profile is ~1GB and almost all of it is refetchable browser cache. Keep places.sqlite
      # and the extension state, drop the rest.
      "**/Firefox/Profiles/*/cache2"
      "**/Firefox/Profiles/*/startupCache"
      "**/Firefox/Profiles/*/shader-cache"
      "**/Firefox/Profiles/*/thumbnails"
      "**/Firefox/Profiles/*/settings/**"
      "**/Firefox/Profiles/*/minidumps"
      "**/Firefox/Profiles/*/datareporting"
      # aw-server rotates .bak copies next to the live DB; the live one is what matters.
      "**/aw-server/*.db.bak.*"
    ];
    notifyBody = ''
      /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
      if [ -r "${ntfyUrlFile}" ] && [ -r "${ntfyTokenFile}" ]; then
        /usr/bin/curl -fsS --max-time 15 \
          -H "Authorization: Bearer $(cat "${ntfyTokenFile}")" \
          -H "Title: restic (mac)" \
          -H "Priority: high" \
          -H "Tags: warning" \
          -d "$1: $2" \
          "$(cat "${ntfyUrlFile}")" >/dev/null 2>&1 || true
      fi'';
    # The first 19 characters are "YYYY-MM-DDTHH:MM:SS". Timestamps arrive both with and without
    # fractional seconds, so with `cut -d. -f1` the latter kept its timezone and failed to parse,
    # and the `|| echo 0` fallback (epoch 0) turned into a bogus "20676 days ago" warning.
    parseSnapshotTime = ''$(date -j -f "%Y-%m-%dT%H:%M:%S" "''${latest:0:19}" +%s 2>/dev/null || echo 0)'';
  };

  # The backup streams the whole set to Drive and must not be reaped mid-flight.
  agent =
    program: schedule:
    import ../lib/launchd-agent.nix {
      inherit program schedule;
      nice = 5;
      longRunning = true;
    };
in
{
  home.packages = [ pkgs.restic ];

  # restic passphrase (stored in sops's defaultSopsFile = secrets/secrets.yaml)
  sops.secrets."restic_password".path = common.passwordFile;

  # env sourced by the Justfile / interactive shell (SSO for repo/password/rclone/archiveTag).
  home.file.".config/restic/env".text = common.envFileText;

  # For ntfy failure notifications (URL is a publish endpoint including the topic, token is a Bearer tk_...).
  #   Even if unset, notify still works with osascript only, so it's harmless.
  sops.secrets."unified_calendar/ntfy_url".path = "${home}/.config/ntfy/url";
  sops.secrets."unified_calendar/ntfy_token".path = "${home}/.config/ntfy/token";

  # Keep Full Disk Access from being lost on rebuild.
  #
  # restic reads under Documents and Library, so it needs Full Disk Access.
  # But TCC identifies grants by the binary's location and signature, so registering a bare
  # store path means **it becomes a different binary on every update and the grant lapses**.
  # In fact, Voice Memos went unreadable and silently dropped out of the backup.
  #
  # The store's restic is ad-hoc signed, so its identity is the cdhash; if the content changes,
  # it is a different binary. Re-signing with a self-signed identity reduces the requirement to
  #   identifier "net.gapul.tcc.restic" and certificate root = H"..."
  # with no cdhash in it. With a fixed location plus this signature, restic is treated as the
  # same binary across updates (verified by measurement).
  #
  # Developer ID is not used because TCC does not check whether the cert is Apple-issued.
  # Code-signing keys are safer the narrower their use, so do not spread them around for TCC.
  #
  # Grant it once: System Settings > Privacy & Security >
  # Full Disk Access, add ~/.local/libexec/tcc/restic.
  home.activation.tccStableRestic = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${../../configs/bin/tcc-stable-binary} \
      ${pkgs.restic}/bin/restic restic || true
  '';

  launchd.agents = {
    # daily 13:00 backup
    restic-backup = agent "${scripts.backup}" [
      {
        Hour = 13;
        Minute = 0;
      }
    ];
  };
}
