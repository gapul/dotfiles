{ config, pkgs, ... }: {
  home.username = "yuki";
  home.homeDirectory = "/Users/yuki";
  home.stateVersion = "23.11";

  programs.home-manager.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    PAGER = "bat";
    HOMEBREW_NO_ANALYTICS = "1";
    PNPM_HOME = "${config.home.homeDirectory}/Library/pnpm";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/Library/pnpm"
    "${config.home.homeDirectory}/Library/pnpm/bin"
    "${config.home.homeDirectory}/.local/bin"  # uv tool 経由のバイナリ
  ];

  # /nix が壊れてもシェルが起動できるようガード付き .zshenv を内製
  home.file.".zshenv" = {
    force = true;
    text = ''
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
      [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ] && \
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    '';
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ".." = "cd ..";
      "..." = "cd ../..";
      g = "git";
      ga = "git add";
      gc = "git commit";
      gl = "git pull";
      gp = "git push";
      gs = "git status";
      ls = "ls -G";
      tl = "textlint --config ~/.config/textlint/.textlintrc.json";
      tlf = "textlint --config ~/.config/textlint/.textlintrc.json --fix";
    };

    initContent = ''
      if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi

      # vi モード + Ctrl+X Ctrl+E で外部エディタ(nvim)起動
      if [[ -o zle ]]; then
        bindkey -v
        KEYTIMEOUT=1
        autoload -Uz edit-command-line
        zle -N edit-command-line
        bindkey -M viins '^X^E' edit-command-line
        bindkey -M vicmd '^X^E' edit-command-line
      fi

      # CocoaPods (nix ruby と衝突回避: ~/.config/fish/setup/install-pod-wrapper.fish を初回実行)
      unset GEM_HOME GEM_PATH

      # Launcher (関数定義 + Ghostty Quick Terminal 常駐ループ)
      [ -f ~/.config/launcher/shells/zsh.sh ] && source ~/.config/launcher/shells/zsh.sh

      # sketchybar 再構成ラッパー (ディスプレイ抜き差し後に呼ぶ)
      function sketchybar-refresh() {
        bash ~/.config/sketchybar/helpers/refresh-displays.sh "$@"
      }

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

      # opam (PATH + 補完)
      [ -r ~/.opam/opam-init/init.zsh ] && source ~/.opam/opam-init/init.zsh > /dev/null 2>&1

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
        local conf="$HOME/vpn-conf/''${profile}.conf"
        if [[ ! -f "$conf" ]]; then
          echo "vpn: config not found: $conf" >&2
          return 1
        fi
        case "$1" in
          up|on|start)   sudo wg-quick up "$conf" ;;
          down|off|stop) sudo wg-quick down "$conf" ;;
          status|st)     sudo wg show ;;
          toggle|"")
            if sudo wg show 2>/dev/null | grep -q "interface: $profile"; then
              sudo wg-quick down "$conf"
            else
              sudo wg-quick up "$conf"
            fi ;;
          *) echo "Usage: vpn {up|down|status|toggle} [profile]"; return 1 ;;
        esac
      }
    '';
  };

  programs.git = {
    enable = true;
    userName = "gapul";
    userEmail = "92638132+gapul@users.noreply.github.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = false;  # sync server 未ログインのため
      search_mode = "fuzzy";
    };
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # dotfiles/configs/* を symlink
  # 静的設定 (yuki が編集 → dotfiles 経由): /nix/store 経由でOK
  home.file.".config/ghostty" = {
    source = ../configs/terminals/ghostty;
    recursive = true;
  };
  home.file.".config/zellij" = {
    source = ../configs/terminals/zellij;
    recursive = true;
  };
  home.file.".config/aerospace" = {
    source = ../configs/wm/aerospace;
    recursive = true;
  };
  home.file.".config/sketchybar" = {
    source = ../configs/wm/sketchybar;
    recursive = true;
  };
  home.file.".config/starship.toml".source = ../configs/shell/starship.toml;
  home.file.".config/gh/config.yml".source = ../configs/cli/gh/config.yml;
  home.file.".config/textlint" = {
    source = ../configs/textlint;
    recursive = true;
  };
  home.file.".ssh/config".source = ../configs/ssh/config;
  home.file.".config/mpv" = {
    source = ../configs/media/mpv;
    recursive = true;
  };
  home.file.".config/launcher/config.toml".source = ../configs/launcher/config.toml;
  home.file.".config/yazi" = {
    source = ../configs/cli/yazi;
    recursive = true;
  };
  home.file.".config/zathura/zathurarc".source = ../configs/cli/zathura/zathurarc;
  home.file.".config/calcurse" = {
    source = ../configs/cli/calcurse;
    recursive = true;
  };

  # 動的設定 (アプリ自身が書き戻す可能性):
  # mkOutOfStoreSymlink で dotfiles の実体に直接 link → 書き込み可能
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/configs/editors/nvim";
  home.file.".config/karabiner".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/configs/keyboard/karabiner";
}
