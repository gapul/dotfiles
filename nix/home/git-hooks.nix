# dotfiles の git hook を home-manager activation で配布する。
# 目的: PR が main にマージされ、本体ツリー (~/.dotfiles) で `git pull` した
# タイミングで、nix/config が変わっていれば自動で `just rebuild` を回す。
#
# 方針 (ryoppippi/dotfiles の nix/modules/home/git-hooks.nix を参考にしつつ縮小):
#   - トリガーは main 更新時のみ = post-merge (pull/merge) + post-rewrite (pull --rebase)。
#     post-commit は入れない。worktree での PR 用コミットで rebuild が走ると
#     「worktree 状態で switch しない」方針に反するため。
#   - worktree では発火させない。hook は共通 .git/hooks を共有するので、
#     toplevel が本体 dotfiles dir のときだけ実行する guard を必ず通す。
#   - 変更パスが nix/ ・ configs/ ・ flake.{nix,lock} ・ Justfile のときだけ回す
#     (configs/ を含めるのは home.file が configs/ をコピーするため = 見た目変更も拾う)。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  dotfilesDir = "${config.home.homeDirectory}/.dotfiles";
  git = "${pkgs.git}/bin/git";

  # nix/config を触る変更を検出したら本体ツリーでのみ `just rebuild`。
  # $1(range) は post-merge=HEAD@{1}..HEAD / post-rewrite=ORIG_HEAD..HEAD。
  guardAndRebuild = range: label: ''
    DOTFILES_DIR="${dotfilesDir}"

    # `just maintain` が内部で叩く git pull からは回さない。maintain は pull の後に
    # 自前で rebuild するため、ここで走ると二重 rebuild になる (maintain が
    # DOTFILES_MAINTAIN=1 を export している)。
    if [ -n "''${DOTFILES_MAINTAIN:-}" ]; then
      exit 0
    fi

    # worktree からは回さない (本体ツリーのみ)。共有 .git/hooks 経由で worktree でも
    # 発火しうるため、toplevel が本体と一致するときだけ続行する。
    if [ "$(${git} rev-parse --show-toplevel 2>/dev/null)" != "$DOTFILES_DIR" ]; then
      exit 0
    fi

    if ${git} diff ${range} --name-only 2>/dev/null \
       | grep -qE '^(flake\.nix|flake\.lock|nix/|configs/|Justfile)'; then
      echo "▶ dotfiles: nix/config が変化 (${label}) → just rebuild を実行"
      # rebuild は本体ツリーの現在状態 (= マージ済み main) を対象にする。
      # just / nh / nix は pull を叩いた対話シェルの PATH を継承して解決する。
      cd "$DOTFILES_DIR" && just rebuild
    fi
  '';

  # post-merge: git pull / git merge の後。引数なし。
  postMerge = pkgs.writeShellScript "dotfiles-post-merge" ''
    set -euo pipefail
    ${guardAndRebuild "HEAD@{1}..HEAD" "merge"}
  '';

  # post-rewrite: git pull --rebase 等の後。$1=rebase のときだけ。
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
