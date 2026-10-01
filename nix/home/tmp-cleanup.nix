{
  config,
  pkgs,
  lib,
  ...
}:
let
  home = config.home.homeDirectory;
  log = "${home}/Library/Logs/tmp-cleanup.log";
  dotfiles = "${home}/.dotfiles";
  toolPath = lib.concatStringsSep ":" [
    "/nix/var/nix/profiles/default/bin"
    "${home}/.nix-profile/bin"
    "${home}/.local/state/nix/profile/bin"
    "/run/current-system/sw/bin"
    "/opt/homebrew/bin"
    "/usr/bin"
    "/bin"
  ];

  # `tmp-cleanup [--dry-run] [dir]`: dir defaults to ~/tmp; --dry-run prints what would go
  # instead of deleting and logging, for testing against a scratch tree or the real ~/tmp.
  cleanupScript = pkgs.writeShellScript "tmp-cleanup" ''
    set -euo pipefail
    # Pinned find/du so -print0/-mmin behave the same on both Macs; git comes from the profile.
    export PATH=${
      lib.makeBinPath [
        pkgs.findutils
        pkgs.coreutils
      ]
    }:${toolPath}:$PATH

    dry=0
    if [ "''${1:-}" = "--dry-run" ]; then
      dry=1
      shift
    fi
    tmp_root="''${1:-${home}/tmp}"

    if [ "$dry" = 0 ]; then
      lock="${home}/.local/state/tmp-cleanup.lock"
      mkdir -p "${home}/.local/state" "${home}/Library/Logs"
      if ! mkdir "$lock" 2>/dev/null; then
        echo "SKIP: another tmp cleanup is running"
        exit 0
      fi
      trap 'rmdir "$lock" 2>/dev/null || true' EXIT
      exec >>"${log}" 2>&1
    fi

    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') ===================="

    if [ ! -d "$tmp_root" ]; then
      echo "$tmp_root not found, skip"
      exit 0
    fi

    # An entry is stale when nothing anywhere inside it (itself included) was modified in the
    # last 7 days. The top-level mtime alone is not enough: writing deep inside a directory
    # doesn't bump it, so a project still in use could look a week old. find doesn't follow
    # symlinks (-P), so a link is judged, and removed, as the link itself.
    count=0
    while IFS= read -r -d "" p; do
      if [ -n "$(find "$p" -mmin -10080 -print -quit 2>/dev/null)" ]; then
        continue
      fi
      # Never delete anything holding a .git (dotfiles worktrees and clones live here): it
      # strands the worktree metadata in the parent repo and takes uncommitted work with it.
      # Report it instead so it can be pushed and removed by hand.
      if [ -e "$p/.git" ]; then
        echo "skipped (git, idle >7d): $p"
        continue
      fi
      size=$(du -sh -- "$p" 2>/dev/null | head -n1 | cut -f1)
      if [ "$dry" = 1 ]; then
        echo "would remove (''${size:-?}): $p"
      else
        rm -rf -- "$p"
        echo "removed (''${size:-?}): $p"
      fi
      count=$((count + 1))
    done < <(find "$tmp_root" -mindepth 1 -maxdepth 1 -print0)
    echo "$count entries $([ "$dry" = 1 ] && echo "would be removed" || echo removed)"

    # A worktree may have been removed by hand already; drop the stale metadata.
    if [ "$dry" = 0 ] && [ -d "${dotfiles}/.git" ]; then
      git -C "${dotfiles}" worktree prune 2>/dev/null || true
    fi
  '';
in
{
  launchd.agents.tmp-cleanup = import ../lib/launchd-agent.nix {
    program = "${cleanupScript}";
    schedule = [
      {
        Hour = 4;
        Minute = 45;
      }
    ];
  };
}
