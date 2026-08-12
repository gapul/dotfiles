# shellcheck shell=bash
# starship の置き換え。出していたもの (cwd / git ブランチ / 2 秒以上かかった実行時間 /
# 終了ステータス) を zsh だけで再現する。
#
# ブランチは .git/HEAD を直接読む。git も vcs_info も呼ばないのでプロンプト 1 回あたり
# のサブプロセスはゼロ。母艦の実測で vcs_info 18.6ms、starship prompt 1.0ms、これ 0.0ms。
#
# 母艦のみ (nix/modules/home/shell.nix が source する)。nssh 先は今も starship なので
# configs/shell/zshrc.remote は触っていない。

setopt PROMPT_SUBST
autoload -Uz add-zsh-hook

# .git を上へ辿ってブランチ名を $_prompt_git に入れる。
# 見つからなければ空 (= プロンプトに何も出ない)。
_prompt_git=""
_prompt_update_git() {
  _prompt_git=""
  local dir=$PWD gitdir head
  while [[ -n $dir ]]; do
    if [[ -d $dir/.git ]]; then
      gitdir=$dir/.git
      break
    elif [[ -f $dir/.git ]]; then
      # worktree / submodule は .git がファイルで "gitdir: <path>" を指す
      gitdir=${"$(<$dir/.git)"#gitdir: }
      [[ $gitdir == /* ]] || gitdir=$dir/$gitdir
      break
    fi
    dir=${dir%/*}
  done
  [[ -n $gitdir && -r $gitdir/HEAD ]] || return
  head="$(<$gitdir/HEAD)"
  if [[ $head == "ref: refs/heads/"* ]]; then
    _prompt_git=" %F{magenta} ${head#ref: refs/heads/}%f"
  else
    # detached HEAD は短縮 sha
    _prompt_git=" %F{magenta} ${head[1,7]}%f"
  fi
}

# 直前のコマンドが 2 秒以上かかったときだけ所要時間を出す (starship の cmd_duration 相当)。
_prompt_dur=""
_prompt_start=-1
_prompt_preexec() { _prompt_start=$SECONDS }
_prompt_update_dur() {
  _prompt_dur=""
  (( _prompt_start >= 0 )) || return
  local -i d=$(( SECONDS - _prompt_start )) m s
  _prompt_start=-1
  (( d >= 2 )) || return
  (( m = d / 60, s = d % 60 ))
  if (( m )); then
    _prompt_dur=" %F{yellow}${m}m${s}s%f"
  else
    _prompt_dur=" %F{yellow}${s}s%f"
  fi
}

# プロンプト末尾の記号。色は直前のコマンドの終了ステータス、形は vi モード。
#   $ = insert (通常)   ❮ = normal (vicmd)
# 色をプロンプト展開時の %(?..) で出すと precmd 自身の戻り値を拾ってしまう
# (ブランチが無いディレクトリで return した瞬間に赤くなる) ので、ここで先に確定させる。
_prompt_status=0
_prompt_keymap=main
_prompt_char='%F{green}$%f'
_prompt_set_char() {
  local color symbol
  (( _prompt_status )) && color=red || color=green
  [[ $_prompt_keymap == vicmd ]] && symbol='❮' || symbol='$'
  _prompt_char="%F{$color}${symbol}%f"
}

_prompt_precmd() {
  _prompt_status=$?
  # zsh は行ごとに main (viins) キーマップへ戻る。precmd はプロンプト描画より前なので
  # ここで戻しておけば、行頭で reset-prompt を撃つ必要がない。
  _prompt_keymap=main
  _prompt_set_char
  _prompt_update_dur
  _prompt_update_git
}
add-zsh-hook preexec _prompt_preexec
add-zsh-hook precmd _prompt_precmd

# モードが変わった瞬間に描き直す。zle -N で zle-keymap-select を直接握ると他の
# プラグインの同名ウィジェットを潰すので、連鎖する add-zle-hook-widget を使う。
if [[ -o zle ]]; then
  autoload -Uz add-zle-hook-widget
  _prompt_keymap_select() {
    _prompt_keymap=$KEYMAP
    _prompt_set_char
    zle reset-prompt
  }
  add-zle-hook-widget keymap-select _prompt_keymap_select
fi

# %3~ = 末尾 3 階層 (starship の truncation_length = 3 相当)
PROMPT='%F{cyan}%3~%f${_prompt_git}${_prompt_dur} ${_prompt_char} '
