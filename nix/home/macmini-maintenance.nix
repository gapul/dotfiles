{
  config,
  pkgs,
  lib,
  ...
}:
let
  home = config.home.homeDirectory;
  log = "${home}/Library/Logs/macmini-storage-cleanup.log";
  toolPath = lib.concatStringsSep ":" [
    "/nix/var/nix/profiles/default/bin"
    "${home}/.nix-profile/bin"
    "${home}/.local/state/nix/profile/bin"
    "/run/current-system/sw/bin"
    "/opt/homebrew/bin"
    "/usr/bin"
    "/bin"
  ];

  cleanupScript = pkgs.writeShellApplication {
    name = "macmini-storage-cleanup";
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    text = ''
      export PATH=${toolPath}:$PATH

      lock="${home}/.local/state/macmini-storage-cleanup.lock"
      /bin/mkdir -p "${home}/.local/state" "${home}/Library/Logs"
      if ! /bin/mkdir "$lock" 2>/dev/null; then
        echo "SKIP: another storage cleanup is running"
        exit 0
      fi
      trap '/bin/rmdir "$lock" 2>/dev/null || true' EXIT
      exec >>"${log}" 2>&1

      echo "==================== $(date '+%Y-%m-%d %H:%M:%S') ===================="
      before=$(/bin/df -k / | /usr/bin/awk 'NR == 2 { print $4 }')

      # Keep only the current generations and active service closures. Old Nix generations are
      # reproducible and were the largest recurring source of reclaimable space here.
      # This runs as the user, so it only drops home-manager generations; the system
      # profile (root) is handled by launchd.daemons.nix-gc in hosts/darwin-common.nix.
      nix-collect-garbage --delete-old || true

      # Package-manager caches are all re-downloadable. Prefer each tool's own pruning
      # semantics instead of deleting implementation-specific directories by hand.
      command -v uv >/dev/null 2>&1 && uv cache prune || true
      command -v pnpm >/dev/null 2>&1 && pnpm store prune || true
      command -v npm >/dev/null 2>&1 && npm cache clean --force || true
      command -v brew >/dev/null 2>&1 && brew cleanup --prune=all || true

      prune_tree_if_stale() {
        path="$1"
        [ -d "$path" ] && [ ! -L "$path" ] || return 0
        # Preserve anything with a file touched in the last 30 days. If a tree is
        # inactive, remove only the explicitly listed, reproducible build output.
        if ! /usr/bin/find "$path" -type f -mtime -30 -print -quit | /usr/bin/grep -q .; then
          size=$(/usr/bin/du -sh "$path" 2>/dev/null | /usr/bin/awk '{ print $1 }')
          /usr/bin/find "$path" -depth -delete
          echo "removed stale build tree ($size): $path"
        fi
      }

      prune_tree_if_stale "${home}/Developer/github.com/LadybirdBrowser/ladybird/Build"
      prune_tree_if_stale "${home}/Developer/github.com/servo/servo/target"
      prune_tree_if_stale "${home}/Developer/github.com/gapul/readest/src-tauri/target"

      # Server-side mobile builds keep large global caches outside each disposable checkout.
      # Retain active caches for incremental builds, but let an unused toolchain relinquish them.
      prune_tree_if_stale "${home}/.local/share/gradle/caches"
      prune_tree_if_stale "${home}/.local/share/gradle/wrapper"
      prune_tree_if_stale "${home}/.cache/pub"

      # DerivedData is per-project and reproducible. Evaluate children separately so
      # one active Xcode project does not retain every inactive project's cache.
      derived="${home}/Library/Developer/Xcode/DerivedData"
      if [ -d "$derived" ]; then
        for path in "$derived"/*; do
          [ -e "$path" ] || continue
          prune_tree_if_stale "$path"
        done
      fi

      # macmini-build owns these clones, so an unused one is entirely reproducible. Active
      # repositories keep their ignored compiler caches for incremental builds.
      build_repos="${home}/.local/state/macmini-build/repos"
      if [ -d "$build_repos" ]; then
        for path in "$build_repos"/*; do
          [ -e "$path" ] || continue
          prune_tree_if_stale "$path"
        done
      fi

      after=$(/bin/df -k / | /usr/bin/awk 'NR == 2 { print $4 }')
      freed=$((after - before))
      echo "free space change: $((freed / 1024)) MiB"
    '';
  };

  # launchd keeps StandardOutPath open for the life of the job, so a log can only be trimmed
  # in place: renaming it would leave the writer on the old inode. launchd opens it O_APPEND,
  # so truncating to 0 is safe and the next write lands at the start. Nothing rotated these
  # before 2026-10-28, when syncclipboard's log was 743 MB and findmy-tag's 38 MB.
  logTrimScript = pkgs.writeShellApplication {
    name = "macmini-log-trim";
    text = ''
      exec >>"${home}/Library/Logs/macmini-log-trim.log" 2>&1
      max=$((20 * 1024 * 1024))
      keep=$((1024 * 1024))
      for f in "${home}"/Library/Logs/*.log "${home}"/.local/state/*/*.log /tmp/*.log; do
        [ -f "$f" ] && [ ! -L "$f" ] && [ -O "$f" ] || continue
        size=$(/usr/bin/stat -f %z "$f")
        [ "$size" -gt "$max" ] || continue
        # Keep the newest 1 MiB beside it, so the lines leading up to a trim are not lost.
        /usr/bin/tail -c "$keep" "$f" >"$f.1"
        : >"$f"
        echo "$(/bin/date '+%F %T') trimmed $f ($((size / 1024 / 1024)) MiB)"
      done
    '';
  };
in
{
  launchd.agents.macmini-log-trim = import ../lib/launchd-agent.nix {
    program = lib.getExe logTrimScript;
    schedule = [
      {
        Hour = 4;
        Minute = 20;
      }
    ];
  };

  launchd.agents.macmini-storage-cleanup = import ../lib/launchd-agent.nix {
    program = lib.getExe cleanupScript;
    schedule = [
      {
        Weekday = 0;
        Hour = 4;
        Minute = 15;
      }
    ];
    longRunning = true;
  };
}
