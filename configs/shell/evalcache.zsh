# shellcheck shell=bash
# `eval "$(foo init zsh)"` 系は起動のたびにサブプロセスを起こす。出力はツールの
# バージョンごとに固定なので、実体パスをキーにキャッシュして source する。
# nix のツールは更新で store パスが変わるため、それだけで自然に無効化される。
#
# 効きは暇なマシンでは地味 (1 本 3〜10ms) だが、負荷がかかっていると 1 本 20〜130ms
# まで伸びる。そこが一番イラつく場面なので、プロセス生成自体を消しておく価値はある。
#
# nix/modules/home/shell.nix が mkOrder 500 で source する。呼び出し側 (cli.nix) は
# home-manager が元々使っていた order をそのまま使いたいので、それより前に居る必要がある。
#
# ponytail: パスが固定のツール (brew 等) は更新してもキャッシュが無効化されない。
#           様子が変なら rm -rf "$_evalcache_dir"。
_evalcache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-evalcache"
evalcache() {
  local bin=${${commands[$1]:-$1}:A}
  local f="$_evalcache_dir/${${(j:_:)@[2,-1]}//\//-}${bin//\//-}.zsh"
  if [[ ! -s $f ]]; then
    mkdir -p "$_evalcache_dir" && "$@" >| "$f" && [[ -s $f ]] || {
      # 生成に失敗したらキャッシュを諦めて素で eval する (壊れた残骸は残さない)
      rm -f -- "$f"
      eval "$("$@")"
      return
    }
  fi
  source "$f"
}
