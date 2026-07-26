# Shell component (ECS: profile)。zsh 一式。
{
  config,
  pkgs,
  ...
}:
{
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh"; # XDG: zsh設定一式を ~/.config/zsh/ へ (ZDOTDIR)。HM 26.05 は絶対パス必須

    envExtra = ''
      # ZDOTDIR が既に環境にある zsh は ~/.zshenv ではなく
      # $ZDOTDIR/.zshenv を読むため、XDG 寄せはここにも置く。
      export CODEX_HOME="$HOME/.local/share/codex"
      export CODEX_SQLITE_HOME="$HOME/.local/state/codex/sqlite"
      export NPM_CONFIG_USERCONFIG="$HOME/.config/npm/npmrc"
      export NPM_CONFIG_CACHE="$HOME/.cache/npm"
      export NPM_CONFIG_PREFIX="$HOME/.local/share/npm"
    '';

    # XDG 化: history → ~/.local/state/zsh/, 補完dump → ~/.cache/zsh/
    history.path = "${config.xdg.stateHome}/zsh/history";
    completionInit = ''
      autoload -U compinit
      compinit -d "${config.xdg.cacheHome}/zsh/zcompdump"
    '';

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    plugins = [
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
      {
        name = "zsh-history-substring-search";
        src = pkgs.zsh-history-substring-search;
        file = "share/zsh-history-substring-search/zsh-history-substring-search.zsh";
      }
    ];

    shellAliases = {
      ".." = "cd ..";
      "..." = "cd ../..";
      g = "git";
      ga = "git add";
      gc = "git commit";
      gl = "git pull";
      gp = "git push";
      gs = "git status";
      keystats = "${config.home.homeDirectory}/.local/bin/keystats";
      tl = "textlint --config ~/.config/textlint/.textlintrc.json";
      tlf = "textlint --config ~/.config/textlint/.textlintrc.json --fix";
      cfw = "~/Developer/github.com/gapul/personal-tools/cloudflare/bin/cf-wrangler";
    };

    initContent = ''
      # XDG: history / 補完dump / vim state 用ディレクトリを確保
      mkdir -p "${config.xdg.stateHome}/zsh" "${config.xdg.cacheHome}/zsh" "${config.xdg.stateHome}/vim"

      # fish 風 setopt (移行時に失った機能の再現)
      setopt AUTO_CD
      setopt AUTO_PUSHD
      setopt PUSHD_IGNORE_DUPS
      setopt EXTENDED_HISTORY
      setopt GLOB_STAR_SHORT
      setopt INTERACTIVE_COMMENTS

      # history-substring-search: Up/Down で先頭一致(fish 風)
      if [[ -o zle ]]; then
        bindkey '^[[A' history-substring-search-up
        bindkey '^[[B' history-substring-search-down
        bindkey -M vicmd 'k' history-substring-search-up
        bindkey -M vicmd 'j' history-substring-search-down
      fi

      # fzf-tab: TAB 補完の preview をスマートに
      zstyle ':completion:*' menu no
      zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons=auto $realpath 2>/dev/null'
      zstyle ':fzf-tab:complete:(\\\\|*/|)git-(add|diff|restore|reset):*' fzf-preview 'git diff --color=always -- $word | delta 2>/dev/null'
      zstyle ':fzf-tab:complete:(\\\\|*/|)git-(checkout|switch):*' fzf-preview 'git log --color=always --oneline -20 $word 2>/dev/null'
      zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps -p $word -o pid,ppid,user,%cpu,%mem,command 2>/dev/null'
      zstyle ':fzf-tab:*' fzf-flags --height=40% --reverse

      # nix build / nix-build を nom (nix-output-monitor) で見やすく
      if command -v nom >/dev/null 2>&1; then
        alias nix-build='nix-build 2>&1 | nom'
        function nix() {
          if [[ "$1" == "build" ]]; then
            shift
            command nix build --log-format internal-json -v "$@" 2>&1 | nom --json
          else
            command nix "$@"
          fi
        }
      fi

      # jd (just-dotfiles): dotfiles の just レシピをどこからでも実行 (cd 不要)。
      #   例: jd rebuild / jd update / jd (引数なしで一覧)
      #   nh は NH_*_FLAKE で flake を env 指定済みなので cwd 非依存。
      #   --working-directory で justfile_directory() 依存レシピ (sketchybar-font 等) も正しく動く。
      function jd() {
        just --justfile "$HOME/.dotfiles/Justfile" --working-directory "$HOME/.dotfiles" "$@"
      }

      # git worktreeを兄弟ディレクトリに作り、`git wt <branch>` で移動する。
      # git-wtのwrapperを保持してから、`git wtpr <PR>` のPR checkoutだけ拡張する。
      eval "$(git wt --init zsh)"
      functions[git-wt-shell]=$functions[git]
      function git() {
        if [[ "$1" == "wtpr" ]]; then
          shift
          local target
          target="$(command git-wtpr "$@")" || return
          if [[ -d "$target" ]]; then
            cd "$target"
          else
            print -r -- "$target"
            return 1
          fi
        else
          git-wt-shell "$@"
        fi
      }

      # 危険なURL、pipe-to-shell、難読化payloadを実行前に検査する。
      # 既定policyはhigh-riskをblock、medium-riskをwarn。常時strictにはしない。
      eval "$(tirith init --shell zsh)"

      # Codex TUI は system theme を持たないため、起動時のOS外観に合わせて
      # Rosé Pine / Dawn のカスタム tmTheme を選ぶ。
      function codex() {
        local codex_theme="rose-pine"
        if command -v defaults >/dev/null 2>&1; then
          if ! defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
            codex_theme="rose-pine-dawn"
          fi
        elif [[ "''${COLORFGBG##*;}" == <8-15> ]]; then
          codex_theme="rose-pine-dawn"
        fi
        command codex -c "tui.theme=\"$codex_theme\"" "$@"
      }

      # vi モード + Ctrl+X Ctrl+E で外部エディタ(nvim)起動
      if [[ -o zle ]]; then
        bindkey -v
        KEYTIMEOUT=1
        autoload -Uz edit-command-line
        zle -N edit-command-line
        bindkey -M viins '^X^E' edit-command-line
        bindkey -M vicmd '^X^E' edit-command-line
        # forward delete (^[[3~) は zsh 既定で未定義 → vi モードでは ESC 誤爆で
        # ノーマルモードに落ち文字化けする。明示 bind して素直に1文字削除させる。
        bindkey -M viins '^[[3~' delete-char
        bindkey -M vicmd '^[[3~' delete-char
      fi

      # Launcher (関数定義 + Ghostty Quick Terminal 常駐ループ)
      [ -f ~/.config/launcher/shells/zsh.sh ] && source ~/.config/launcher/shells/zsh.sh

      # Claude Code: 名前付きセッション launcher (作成 or 再開)
      function cl() {
        local name=$1
        if [[ -z "$name" ]]; then
          echo "Usage: cl <session-name> [claude options...]"
          return 1
        fi
        local id=$(printf "%s:%s" "$PWD" "$name" | shasum -a 256 | cut -c1-32 \
          | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/')
        claude -n "$name" --resume "$id" "''${@:2}" 2>/dev/null \
          || claude --session-id "$id" -n "$name" "''${@:2}"
      }

      # ghq + fzf: Ctrl+] で repo 横断 fuzzy 移動
      function ghq-fzf() {
        local selected
        selected=$(ghq list 2>/dev/null | fzf --height=40% --reverse \
          --preview "fzf-preview-repo $(ghq root)/{}" \
          --preview-window=right:60%)
        if [[ -n "$selected" ]]; then
          BUFFER="cd $(ghq root)/$selected"
          zle accept-line
        fi
        zle reset-prompt
      }
      zle -N ghq-fzf
      bindkey '^]' ghq-fzf

      function gita-sync() {
        if ! command -v gita >/dev/null || ! command -v ghq >/dev/null; then
          echo "gita / ghq が無い"
          return 1
        fi
        ghq list -p | xargs -I {} gita add {} 2>&1 | tail -3
        echo "登録済 repo: $(gita ls | wc -w | tr -d ' ')"
      }

      function mkcd() { mkdir -p "$1" && cd "$1"; }

      function extract() {
        case $1 in
          *.tar.bz2) tar xjf $1 ;;  *.tar.gz)  tar xzf $1 ;;
          *.bz2)     bunzip2 $1 ;;  *.rar)     unrar x $1 ;;
          *.gz)      gunzip $1 ;;   *.tar)     tar xf $1 ;;
          *.tbz2)    tar xjf $1 ;;  *.tgz)     tar xzf $1 ;;
          *.zip)     unzip $1 ;;    *.Z)       uncompress $1 ;;
          *.7z)      7z x $1 ;;
          *)         echo "'$1' cannot be extracted" ;;
        esac
      }

      function vpn() {
        local profile="''${2:-wgcf-profile}"
        local conf="$HOME/.config/wireguard/''${profile}.conf"
        if [[ ! -f "$conf" ]]; then
          echo "vpn: config not found: $conf" >&2
          return 1
        fi
        case "$1" in
          up|on|start)   sudo wg-quick up "$conf" ;;
          down|off|stop) sudo wg-quick down "$conf" ;;
          status|st)     sudo wg show ;;
          toggle|"")
            # macOS は interface 名が utunN になるため wg show では profile 名で判定不可。
            # wg-quick が up 中だけ作る /var/run/wireguard/<profile>.name の有無で判定する。
            if sudo test -f "/var/run/wireguard/''${profile}.name"; then
              sudo wg-quick down "$conf"
            else
              sudo wg-quick up "$conf"
            fi ;;
          *) echo "Usage: vpn {up|down|status|toggle} [profile]"; return 1 ;;
        esac
      }
    '';
  };
}
