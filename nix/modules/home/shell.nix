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
    # Full compinit (with its compaudit fpath scan) costs ~58ms of the ~350ms
    # startup. Run it for real once a day, otherwise trust the dump (-C).
    # New completions from a rebuild show up within 24h, or immediately after
    # rm ~/.cache/zsh/zcompdump.
    completionInit = ''
      autoload -Uz compinit
      _zcompdump="${config.xdg.cacheHome}/zsh/zcompdump"
      if [[ -n $_zcompdump(#qN.mh-24) ]]; then
        compinit -C -d "$_zcompdump"
      else
        compinit -d "$_zcompdump"
      fi
      unset _zcompdump
      # bash-style completions (`complete` / `compgen`). /etc/zshrc used to set this up,
      # but it only works once compinit has run, so it belongs here now.
      autoload -Uz bashcompinit && bashcompinit
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
      # (keystats alias removed: the cask links the CLI into /opt/homebrew/bin, and the alias was
      #  pinning an older hand-built copy in ~/.local/bin ahead of it.)
      # Portable aliases (.. / g / gs etc.) live in configs/shell/zshrc.common so nssh
      # hosts get them too. Only Mac-specific paths stay here.
      tl = "textlint --config ~/.config/textlint/.textlintrc.json";
      tlf = "textlint --config ~/.config/textlint/.textlintrc.json --fix";
      cfw = "~/Developer/github.com/gapul/personal-tools/cloudflare/bin/cf-wrangler";
    };

    initContent = ''
      # XDG: ensure directories for history / completion dump / vim state exist
      mkdir -p "${config.xdg.stateHome}/zsh" "${config.xdg.cacheHome}/zsh" "${config.xdg.stateHome}/vim"

      # Settings shared with nssh hosts: setopt / keybindings / fzf-tab zstyles /
      # portable aliases and functions. nssh hosts read the very same file from
      # configs/shell/zshrc.remote, so the two never drift.
      # Host-specific things (ghq / tirith / git-wt / launcher / vpn / codex theme)
      # stay below, because they depend on tools only this machine has.
      source ${../../../configs/shell/zshrc.common}

      # Prompt. starship was dropped on 2026-08-12: the cwd is the only part that got read,
      # and it cost a subprocess at every startup plus one at every redraw. Plain zsh covers it.
      # nssh hosts and Windows still use starship (configs/shell/starship.toml), so that config stays.
      # If the git branch is wanted back here, vcs_info is the zsh-native way to get it.
      PROMPT='%F{cyan}%~%f %F{green}$%f '

      # jd (just-dotfiles): run the dotfiles just recipes from anywhere (no cd needed).
      #   e.g.: jd rebuild / jd update / jd (no args lists them)
      #   nh already specifies the flake via NH_*_FLAKE env, so it is cwd-independent.
      #   --working-directory makes justfile_directory()-dependent recipes (sketchybar-font etc.) work correctly too.
      function jd() {
        just --justfile "$HOME/.dotfiles/Justfile" --working-directory "$HOME/.dotfiles" "$@"
      }

      # Create git worktrees in sibling directories and jump there via `git wt <branch>`.
      # Keep git-wt's wrapper, then extend only the PR checkout of `git wtpr <PR>`.
      # git wt と git-wt は同じ出力なので、キャッシュキーが git 本体に化けない後者を叩く。
      evalcache git-wt --init zsh
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
      evalcache tirith init --shell zsh

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
