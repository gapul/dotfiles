# Distribute the dotfiles git hooks via home-manager activation.
# Purpose: when a PR is merged to main and `git pull` is run in the main tree (~/.dotfiles),
# automatically run `just rebuild` if nix/config has changed.
#
# Approach (modeled on ryoppippi/dotfiles' nix/modules/home/git-hooks.nix, scaled down):
#   - Trigger only on main updates = post-merge (pull/merge) + post-rewrite (pull --rebase).
#     Don't add post-commit. Running rebuild on a worktree's PR commit would violate
#     the "don't switch while in a worktree state" policy.
#   - Don't fire in worktrees. Hooks share the common .git/hooks, so always pass a guard
#     that runs only when toplevel is the main dotfiles dir.
#   - Run only when changed paths touch nix/ , configs/ , flake.{nix,lock} , or Justfile
#     (configs/ is included because home.file copies configs/ = it picks up appearance changes too).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  dotfilesDir = "${config.home.homeDirectory}/.dotfiles";
  git = "${pkgs.git}/bin/git";

  # When a change touching nix/config is detected, run `just rebuild` in the main tree only.
  # $1 (range) is post-merge=HEAD@{1}..HEAD / post-rewrite=ORIG_HEAD..HEAD.
  guardAndRebuild = range: label: ''
    DOTFILES_DIR="${dotfilesDir}"

    # Don't run from the git pull that `just maintain` invokes internally. maintain runs its own
    # rebuild after the pull, so running here would cause a double rebuild (maintain
    # exports DOTFILES_MAINTAIN=1).
    if [ -n "''${DOTFILES_MAINTAIN:-}" ]; then
      exit 0
    fi

    # Don't run from worktrees (main tree only). It could fire in a worktree via the shared
    # .git/hooks, so continue only when toplevel matches the main tree.
    if [ "$(${git} rev-parse --show-toplevel 2>/dev/null)" != "$DOTFILES_DIR" ]; then
      exit 0
    fi

    if ${git} diff ${range} --name-only 2>/dev/null \
       | grep -qE '^(flake\.nix|flake\.lock|nix/|configs/|Justfile)'; then
      echo "▶ dotfiles: nix/config changed (${label}) → running just rebuild"
      # rebuild targets the main tree's current state (= merged main).
      # just / nh / nix resolve by inheriting the PATH of the interactive shell that ran the pull.
      cd "$DOTFILES_DIR" && just rebuild
    fi
  '';

  # post-merge: after git pull / git merge. No arguments.
  postMerge = pkgs.writeShellScript "dotfiles-post-merge" ''
    set -euo pipefail
    ${guardAndRebuild "HEAD@{1}..HEAD" "merge"}
  '';

  # post-rewrite: after git pull --rebase etc. Only when $1=rebase.
  postRewrite = pkgs.writeShellScript "dotfiles-post-rewrite" ''
    set -euo pipefail
    [ "''${1:-}" = "rebase" ] || exit 0
    ${guardAndRebuild "ORIG_HEAD..HEAD" "rebase"}
  '';
in
{
  home.activation.installDotfilesRebuildHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "${dotfilesDir}/.git" ]; then
      run /bin/mkdir -p "${dotfilesDir}/.git/hooks"
      run /usr/bin/install -m 0755 ${postMerge} "${dotfilesDir}/.git/hooks/post-merge"
      run /usr/bin/install -m 0755 ${postRewrite} "${dotfilesDir}/.git/hooks/post-rewrite"
    fi
  '';
}
