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

  cleanupScript = pkgs.writeShellScript "tmp-cleanup" ''
    set -uo pipefail
    export PATH=${toolPath}:$PATH

    lock="${home}/.local/state/tmp-cleanup.lock"
    mkdir -p "${home}/.local/state" "${home}/Library/Logs"
    if ! mkdir "$lock" 2>/dev/null; then
      echo "SKIP: another tmp cleanup is running"
      exit 0
    fi
    trap 'rmdir "$lock" 2>/dev/null || true' EXIT
    exec >>"${log}" 2>&1

    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') ===================="

    tmp_root="${home}/tmp"
    if [ ! -d "$tmp_root" ]; then
      echo "$tmp_root not found, skip"
      exit 0
    fi

    # Same rule as `just gc-deep`'s ~/tmp sweep, unattended and at 7 days: skip anything
    # holding a .git (worktrees/clones), since deleting one behind git's back strands its
    # metadata in the parent repo and takes any uncommitted work with it.
    count=0
    while IFS= read -r p; do
      size=$(du -sh "$p" 2>/dev/null | cut -f1)
      rm -rf -- "$p"
      echo "removed (''${size:-?}): $p"
      count=$((count + 1))
    done < <(find "$tmp_root" -mindepth 1 -maxdepth 1 -mtime +7 ! -exec test -e {}/.git \; -print)
    echo "$count entries removed"

    # A worktree may have been removed by hand already; drop the stale metadata.
    [ -d "${dotfiles}/.git" ] && git -C "${dotfiles}" worktree prune 2>/dev/null
    true
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
