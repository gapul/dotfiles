# Unit test for the evalcache helper in configs/shell/zshrc.common.
# It caches `eval "$(tool init zsh)"` output, so the three things that must hold are:
# the first call evaluates and stores, later calls serve the store even if the tool is
# gone, and empty output falls back instead of caching a useless file.
{ pkgs }:
let
  evalcacheZsh = ../../configs/shell/evalcache.zsh;
in
pkgs.runCommand "evalcache-test"
  {
    nativeBuildInputs = [ pkgs.zsh ];
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME" "$TMPDIR/bin"

    cat > "$TMPDIR/bin/greeter" <<'SH'
    #!/bin/sh
    echo 'export EVALCACHE_PROBE=hit'
    SH
    : > "$TMPDIR/bin/silent"
    chmod +x "$TMPDIR/bin/greeter" "$TMPDIR/bin/silent"

    zsh -f -c '
      source ${evalcacheZsh}

      evalcache '"$TMPDIR"'/bin/greeter init zsh
      [[ $EVALCACHE_PROBE == hit ]] || { print -u2 "miss: first call did not evaluate"; exit 1 }

      # Break the tool: the cached copy must still be what gets sourced.
      print -r "#!/bin/sh\nexit 1" > '"$TMPDIR"'/bin/greeter
      unset EVALCACHE_PROBE
      evalcache '"$TMPDIR"'/bin/greeter init zsh
      [[ $EVALCACHE_PROBE == hit ]] || { print -u2 "miss: cached output was not reused"; exit 1 }

      # Empty output is never worth caching; it must not leave a file behind.
      evalcache '"$TMPDIR"'/bin/silent init zsh
      if print -l "$XDG_CACHE_HOME"/zsh-evalcache/*silent*(N) | grep -q silent; then
        print -u2 "empty output got cached"; exit 1
      fi
    '

    touch $out
  ''
