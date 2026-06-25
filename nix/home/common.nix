{ config, pkgs, lib, user, ... }: {
  # OS 非依存の home-manager 設定
  # OS 固有の部分は home/darwin.nix / home/linux.nix / home/wsl.nix 等に分離

  home.username = user.username;
  home.stateVersion = "23.11";

  programs.home-manager.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    PAGER = "bat";
    SOPS_AGE_KEY_FILE = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    CLAUDE_CONFIG_DIR = "${config.home.homeDirectory}/.config/claude";  # Claude Code を XDG 配下へ
    # テレメトリ無効化。isTelemetryEnabled() が false になり logEvent が短絡するので、
    # 送信スプール ~/.claude/telemetry (CLAUDE_CONFIG_DIR を見ずハードコード) 自体が作られない。
    # フル無効化(エラー報告/feedback/autoupdater も)は CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1。
    DISABLE_TELEMETRY = "1";

    # XDG Base Directory: 実行時に $XDG_* を参照する CLI 向けに明示 export
    # (home-manager はビルド時に config.xdg.* を展開するだけで env には出さないため)
    XDG_CONFIG_HOME = config.xdg.configHome;
    XDG_DATA_HOME   = config.xdg.dataHome;
    XDG_STATE_HOME  = config.xdg.stateHome;
    XDG_CACHE_HOME  = config.xdg.cacheHome;

    # cargo (Homebrew 製 rustc/cargo): ~/.cargo → XDG_DATA。bin は sessionPath に追加
    CARGO_HOME = "${config.xdg.dataHome}/cargo";

    # npm (Homebrew 製): cache/userconfig を XDG へ移し ~/.npm の自動生成を抑止
    NPM_CONFIG_CACHE      = "${config.xdg.cacheHome}/npm";
    NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/npmrc";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"  # uv tool 経由のバイナリ
    "${config.home.homeDirectory}/bin"          # home.file."bin/*" 経由のスクリプト
    "${config.xdg.dataHome}/cargo/bin"          # cargo install のバイナリ (CARGO_HOME/bin)
  ];

  # npm (Homebrew) 用 XDG npmrc。NPM_CONFIG_USERCONFIG の指す実体
  xdg.configFile."npm/npmrc".text = ''
    cache=${config.xdg.cacheHome}/npm
  '';

  # /nix が壊れてもシェルが起動できるようガード付き .zshenv を内製
  home.file.".zshenv" = {
    force = true;
    text = ''
      export ZDOTDIR="$HOME/.config/zsh"
      # CLAUDE_CONFIG_DIR は home.sessionVariables にもあるが、hm-session-vars.sh の
      # __HM_SESS_VARS_SOURCED ガードで再 source されず空になる事故 (古いシェル / GUI 起動)
      # を避けるため、ガード無しの .zshenv でも明示 export しておく。
      export CLAUDE_CONFIG_DIR="$HOME/.config/claude"
      # HISTFILE も .zshrc を読まない古い/GUI 起動シェルが ~/.zsh_history へ
      # 漏らさないよう、ガード無しの .zshenv で XDG パスを先に固定しておく。
      export HISTFILE="$HOME/.local/state/zsh/history"
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
      [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ] && \
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    '';
  };

  programs.zsh = {
    enable = true;
    dotDir = ".config/zsh";  # XDG: zsh設定一式を ~/.config/zsh/ へ (ZDOTDIR)

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
      tl = "textlint --config ~/.config/textlint/.textlintrc.json";
      tlf = "textlint --config ~/.config/textlint/.textlintrc.json --fix";
    };

    initContent = ''
      # XDG: history / 補完dump 用ディレクトリを確保
      mkdir -p "${config.xdg.stateHome}/zsh" "${config.xdg.cacheHome}/zsh"

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

      # vi モード + Ctrl+X Ctrl+E で外部エディタ(nvim)起動
      if [[ -o zle ]]; then
        bindkey -v
        KEYTIMEOUT=1
        autoload -Uz edit-command-line
        zle -N edit-command-line
        bindkey -M viins '^X^E' edit-command-line
        bindkey -M vicmd '^X^E' edit-command-line
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

  # 単発で使う CLI ツール群 (programs.* の対象外、OS 非依存)
  home.packages = with pkgs; [
    comma                 # `, pkg args` で install せず nix package を実行
    nix-output-monitor    # nh / nix build を見やすくする (`nom`)
    nix-tree              # nix store 依存関係 TUI
    nix-init              # flake.nix 雛形生成
    devenv                # Nix ベース dev shell (direnv と組み合わせ)
    tealdeer              # tldr CLI (programs.tealdeer は archive_source 非対応のため手動)
  ];

  programs.git = {
    enable = true;
    userName = user.gitUser;
    userEmail = user.gitEmail;
    delta = {
      enable = true;
      options = {
        navigate = true;
        line-numbers = true;
        side-by-side = true;
      };
    };
    ignores = [
      ".DS_Store"
      ".AppleDouble"
      ".LSOverride"
      "Thumbs.db"
      ".idea/"
      ".vscode/"
      "*.swp"
      "*.swo"
      ".direnv/"
      "result"
      "result-*"
      ".envrc.local"
      ".claude/settings.local.json"
    ];
    signing = {
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      ghq.root = "${config.home.homeDirectory}/ghq";
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
      gpg.format = "ssh";
      "gpg \"ssh\"".allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";
    };
  };

  programs.bat = {
    enable = true;
    config = { style = "numbers,changes,header"; };
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    git = true;
    icons = "auto";
    extraOptions = [ "--group-directories-first" ];
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
    # Up は history-substring-search に明け渡す。atuin は Ctrl+R のみで起動
    flags = [ "--disable-up-arrow" ];
    settings = {
      # 公式 SaaS で複数端末 (Mac / WSL / Linux server) の history を同期。
      # 利用前に各端末で 1 度だけ `atuin login -u gapul` (or register) が必要。
      # E2E 暗号化キーは ~/.local/share/atuin/key、Bitwarden に backup 推奨。
      auto_sync = true;
      sync_address = "https://api.atuin.sh";
      sync_frequency = "5m";
      update_check = false;
      search_mode = "fuzzy";
      filter_mode = "global";    # 全 host 横断検索
      style = "compact";
      inline_height = 20;
      enter_accept = false;      # Enter で実行せず編集に
      show_preview = true;
    };
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # nh: nh darwin / nh home の便利ラッパー
  programs.nh = {
    enable = true;
    flake = "${config.home.homeDirectory}/dotfiles/nix";
  };

  # SOPS: 暗号化された secrets を home-manager switch 時に decrypt
  # (path に ~/Library が無いものは OS 非依存)
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/secrets.yaml;
    secrets = {
      "vpn/proton".path     = "${config.home.homeDirectory}/.config/wireguard/proton.conf";
      "vpn/wgcf".path       = "${config.home.homeDirectory}/.config/wireguard/wgcf-profile.conf";
      "rclone_conf".path    = "${config.home.homeDirectory}/.config/rclone/rclone.conf";
      "ssh_config".path     = "${config.home.homeDirectory}/.ssh/config";

      # PII 単一ソース
      "pii/name" = {};
      "pii/email_personal" = {};
      "pii/email_school" = {};
      "pii/email_work" = {};
      "pii/gmail_app_password_mail" = {};
      "pii/gmail_app_password_caldav" = {};
    };

    # aerc / calcurse の template は OS 非依存(`~/.config/...`)
    templates = {
      "aerc-accounts.conf" = {
        path = "${config.home.homeDirectory}/.config/aerc/accounts.conf";
        content = ''
          [Gmail]
          source = imaps://${config.sops.placeholder."pii/email_personal"}@imap.gmail.com:993
          source-cred-cmd = echo "${config.sops.placeholder."pii/gmail_app_password_mail"}"
          outgoing = smtps+plain://${config.sops.placeholder."pii/email_personal"}@smtp.gmail.com:465
          outgoing-cred-cmd = echo "${config.sops.placeholder."pii/gmail_app_password_mail"}"
          from = ${config.sops.placeholder."pii/name"} <${config.sops.placeholder."pii/email_personal"}>
          copy-to = Sent
        '';
      };

      "calcurse-caldav-config" = {
        path = "${config.home.homeDirectory}/.config/calcurse/caldav/config";
        content = ''
          [General]
          SyncDir = ~/.local/share/calcurse/
          SpawnEditor = vi

          [CalDAV]
          ServerAddress = www.google.com
          ServerPort = 443
          ServerPath = /calendar/dav/${config.sops.placeholder."pii/email_personal"}/events/
          InsecureSSL = No
          Verbose = Yes

          [Auth]
          Username = ${config.sops.placeholder."pii/email_personal"}
          Password = ${config.sops.placeholder."pii/gmail_app_password_caldav"}
        '';
      };
    };
  };

  # dotfiles/configs/* を symlink (OS 非依存なものだけ。Mac 専用 = aerospace/sketchybar/karabiner は home/darwin.nix へ)
  home.file.".config/zellij" = {
    source = ../../configs/terminals/zellij;
    recursive = true;
  };
  home.file.".config/starship.toml".source = ../../configs/shell/starship.toml;
  home.file.".config/gh/config.yml".source = ../../configs/cli/gh/config.yml;
  home.file.".config/textlint" = {
    source = ../../configs/textlint;
    recursive = true;
  };
  home.file.".config/mpv" = {
    source = ../../configs/media/mpv;
    recursive = true;
  };
  home.file.".config/launcher/config.toml".source = ../../configs/launcher/config.toml;
  home.file."bin/nssh" = {
    source = ../../configs/bin/nssh;
    executable = true;
  };
  home.file."bin/fzf-preview-repo" = {
    source = ../../configs/bin/fzf-preview-repo;
    executable = true;
  };
  home.file.".config/yazi" = {
    source = ../../configs/cli/yazi;
    recursive = true;
  };
  home.file.".config/zathura/zathurarc".source = ../../configs/cli/zathura/zathurarc;
  home.file.".config/calcurse" = {
    source = ../../configs/cli/calcurse;
    recursive = true;
  };

  # nvim は dotfiles に直接書き戻したいので mkOutOfStoreSymlink
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/configs/editors/nvim";
}
