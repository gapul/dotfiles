# ZDOTDIR プリセット済み / GUI・古いシェル 用の XDG 寄せ export の SSO。
#
# 同じ export が .zshenv (nix/home/common.nix・ガード無し) と
# programs.zsh.envExtra (nix/modules/home/shell.nix) に二重リテラルで書かれていたので集約。
# ここを直せば両方が追従する。値は sessionVariables (common.nix) の config.xdg.* 由来と
# 一致させること (絶対パス vs $HOME 形式の差はあれど同じ実パスを指す)。
#
# 末尾改行は付けない (呼び出し側が改行位置を制御し、生成テキストを不変に保つため)。
{
  codex = ''
    export CODEX_HOME="$HOME/.local/share/codex"
    export CODEX_SQLITE_HOME="$HOME/.local/state/codex/sqlite"'';

  npm = ''
    export NPM_CONFIG_USERCONFIG="$HOME/.config/npm/npmrc"
    export NPM_CONFIG_CACHE="$HOME/.cache/npm"
    export NPM_CONFIG_PREFIX="$HOME/.local/share/npm"'';
}
