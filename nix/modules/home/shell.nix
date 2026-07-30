# Shell component (ECS: profile). Full zsh setup.
{
  config,
  pkgs,
  ...
}:
let
  # SSO for XDG-oriented exports (shared with common.nix's .zshenv).
  xdgEnv = import ../../lib/shell-xdg-env.nix;
in
{
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh"; # XDG: move the whole zsh config to ~/.config/zsh/ (ZDOTDIR). HM 26.05 requires an absolute path

    envExtra = ''
      # When ZDOTDIR is already in the environment, zsh reads $ZDOTDIR/.zshenv
      # instead of ~/.zshenv, so put the XDG-oriented exports here too.
      ${xdgEnv.codex}
      ${xdgEnv.npm}
    '';

    # XDG-ify: history -> ~/.local/state/zsh/, completion dump -> ~/.cache/zsh/
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
      # XDG: ensure directories for history / completion dump / vim state exist
      mkdir -p "${config.xdg.stateHome}/zsh" "${config.xdg.cacheHome}/zsh" "${config.xdg.stateHome}/vim"

      # fish-like setopt (reproducing features lost in the migration)
      setopt AUTO_CD
      setopt AUTO_PUSHD
      setopt PUSHD_IGNORE_DUPS
      setopt EXTENDED_HISTORY
      setopt GLOB_STAR_SHORT
      setopt INTERACTIVE_COMMENTS

      # history-substring-search: Up/Down for prefix match (fish-like)
      if [[ -o zle ]]; then
        bindkey '^[[A' history-substring-search-up
        bindkey '^[[B' history-substring-search-down
        bindkey -M vicmd 'k' history-substring-search-up
        bindkey -M vicmd 'j' history-substring-search-down
      fi

      # fzf-tab: smarter previews for TAB completion
      zstyle ':completion:*' menu no
      zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons=auto $realpath 2>/dev/null'
      zstyle ':fzf-tab:complete:(\\\\|*/|)git-(add|diff|restore|reset):*' fzf-preview 'git diff --color=always -- $word | delta 2>/dev/null'
      zstyle ':fzf-tab:complete:(\\\\|*/|)git-(checkout|switch):*' fzf-preview 'git log --color=always --oneline -20 $word 2>/dev/null'
      zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps -p $word -o pid,ppid,user,%cpu,%mem,command 2>/dev/null'
      zstyle ':fzf-tab:*' fzf-flags --height=40% --reverse

      # make nix build / nix-build more readable via nom (nix-output-monitor)
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

      # jd (just-dotfiles): run the dotfiles just recipes from anywhere (no cd needed).
      #   e.g.: jd rebuild / jd update / jd (no args lists them)
      #   nh already specifies the flake via NH_*_FLAKE env, so it is cwd-independent.
      #   --working-directory makes justfile_directory()-dependent recipes (sketchybar-font etc.) work correctly too.
      function jd() {
        just --justfile "$HOME/.dotfiles/Justfile" --working-directory "$HOME/.dotfiles" "$@"
      }

      # Create git worktrees in sibling directories and jump there via `git wt <branch>`.
      # Keep git-wt's wrapper, then extend only the PR checkout of `git wtpr <PR>`.
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

      # Inspect dangerous URLs, pipe-to-shell, and obfuscated payloads before running.
      # Default policy blocks high-risk and warns on medium-risk; not always strict.
      eval "$(tirith init --shell zsh)"

      # The Codex TUI has no system theme, so pick the custom Rosé Pine / Dawn tmTheme
      # matching the OS appearance at startup.
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

      # vi mode + Ctrl+X Ctrl+E to launch an external editor (nvim)
      if [[ -o zle ]]; then
        bindkey -v
        KEYTIMEOUT=1
        autoload -Uz edit-command-line
        zle -N edit-command-line
        bindkey -M viins '^X^E' edit-command-line
        bindkey -M vicmd '^X^E' edit-command-line
        # forward delete (^[[3~) is undefined by default in zsh -> in vi mode the ESC
        # misfires, dropping to normal mode and garbling input. Bind it explicitly to just delete one char.
        bindkey -M viins '^[[3~' delete-char
        bindkey -M vicmd '^[[3~' delete-char
      fi

      # Launcher (function definitions + Ghostty Quick Terminal resident loop)
      [ -f ~/.config/launcher/shells/zsh.sh ] && source ~/.config/launcher/shells/zsh.sh

      # Claude Code: named-session launcher (create or resume)
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

      # ghq + fzf: Ctrl+] for fuzzy jumping across repos
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
          echo "gita / ghq not found"
          return 1
        fi
        ghq list -p | xargs -I {} gita add {} 2>&1 | tail -3
        echo "registered repos: $(gita ls | wc -w | tr -d ' ')"
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
            # On macOS the interface name is utunN, so wg show cannot decide by profile name.
            # Decide by the presence of /var/run/wireguard/<profile>.name, which wg-quick creates only while up.
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
