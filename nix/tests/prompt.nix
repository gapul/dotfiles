# Unit test for configs/shell/prompt.zsh (the starship replacement).
# The branch lookup walks the filesystem and parses .git by hand, so the shapes that
# matter are checked here: a plain repo, a subdirectory, a detached HEAD, a worktree
# whose .git is a file, and a directory under no repo at all. The status colour and the
# 2-second duration threshold are checked too, since both are easy to break silently.
{ pkgs }:
let
  promptZsh = ../../configs/shell/prompt.zsh;
in
pkgs.runCommand "prompt-test"
  {
    nativeBuildInputs = [ pkgs.zsh ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    # Repo shapes, built by hand so the test needs no git.
    mkdir -p "$TMPDIR/plain/.git" "$TMPDIR/deep/sub/dir/.git" "$TMPDIR/detached/.git" \
             "$TMPDIR/worktree" "$TMPDIR/elsewhere.git" "$TMPDIR/bare"
    echo 'ref: refs/heads/main' > "$TMPDIR/plain/.git/HEAD"
    echo 'ref: refs/heads/feature/deep' > "$TMPDIR/deep/sub/dir/.git/HEAD"
    echo '0123456789abcdef0123456789abcdef01234567' > "$TMPDIR/detached/.git/HEAD"
    echo 'ref: refs/heads/wt' > "$TMPDIR/elsewhere.git/HEAD"
    echo "gitdir: $TMPDIR/elsewhere.git" > "$TMPDIR/worktree/.git"
    mkdir -p "$TMPDIR/deep/sub/dir/nested/deeper"

    zsh -f -c '
      source ${promptZsh}

      check() {  # check <dir> <expected branch, "" for none>
        cd $1
        _prompt_update_git
        # The branch is always the tail of the segment, right before the colour reset.
        if [[ -n $2 ]]; then
          [[ $_prompt_git == *"$2%f" ]] || {
            print -u2 "$1: expected branch [$2], got [$_prompt_git]"; exit 1
          }
        else
          [[ -z $_prompt_git ]] || {
            print -u2 "$1: expected no branch, got [$_prompt_git]"; exit 1
          }
        fi
      }

      check '"$TMPDIR"'/plain                      main
      check '"$TMPDIR"'/deep/sub/dir               feature/deep
      check '"$TMPDIR"'/deep/sub/dir/nested/deeper feature/deep
      check '"$TMPDIR"'/detached                   0123456
      check '"$TMPDIR"'/worktree                   wt
      check '"$TMPDIR"'/bare                       ""

      # The status colour has to reflect the command before the prompt, not precmd itself.
      # Without the explicit capture, a directory with no branch turns the prompt red.
      cd '"$TMPDIR"'/bare
      true;  _prompt_precmd; [[ $_prompt_char == *green* ]] || { print -u2 "ok status not green"; exit 1 }
      false; _prompt_precmd; [[ $_prompt_char == *red* ]]   || { print -u2 "error status not red"; exit 1 }

      # vi mode: the symbol tracks the keymap, the colour keeps tracking the exit status,
      # and precmd puts it back to insert because zsh resets the keymap on every new line.
      vimode() {  # vimode <keymap> <status> <expected symbol> <expected colour>
        _prompt_keymap=$1 _prompt_status=$2
        _prompt_set_char
        [[ $_prompt_char == *"$3"* && $_prompt_char == *"$4"* ]] || {
          print -u2 "keymap=$1 status=$2: expected [$3/$4], got [$_prompt_char]"; exit 1
        }
      }
      vimode main  0 "\$" green
      vimode main  1 "\$" red
      vimode vicmd 0 "❮"  green
      vimode vicmd 1 "❮"  red
      _prompt_keymap=vicmd; true; _prompt_precmd
      [[ $_prompt_char == *"\$"* ]] || { print -u2 "precmd did not return to insert: [$_prompt_char]"; exit 1 }

      # Duration only shows from 2s up, and rolls over into minutes.
      _prompt_preexec; SECONDS=$(( SECONDS + 1 ));   _prompt_precmd
      [[ -z $_prompt_dur ]] || { print -u2 "1s should be silent, got [$_prompt_dur]"; exit 1 }
      _prompt_preexec; SECONDS=$(( SECONDS + 5 ));   _prompt_precmd
      [[ $_prompt_dur == *5s* ]] || { print -u2 "5s missing, got [$_prompt_dur]"; exit 1 }
      _prompt_preexec; SECONDS=$(( SECONDS + 125 )); _prompt_precmd
      [[ $_prompt_dur == *2m5s* ]] || { print -u2 "2m5s missing, got [$_prompt_dur]"; exit 1 }
      # ...and it clears on the next prompt instead of sticking around.
      _prompt_precmd
      [[ -z $_prompt_dur ]] || { print -u2 "duration stuck at [$_prompt_dur]"; exit 1 }
    '

    touch $out
  ''
