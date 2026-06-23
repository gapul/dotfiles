{ config, pkgs, lib, user, ... }: {
  home.username = user.username;
  home.homeDirectory = "/Users/${user.username}";
  home.stateVersion = "23.11";

  programs.home-manager.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    PAGER = "bat";
    HOMEBREW_NO_ANALYTICS = "1";
    PNPM_HOME = "${config.home.homeDirectory}/Library/pnpm";
    SOPS_AGE_KEY_FILE = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    # nh 4.x: programs.nh.flake は古い FLAKE 変数しか set しないので、
    # darwinConfigurations.<user> / homeConfigurations.<user> まで明示。
    # home は activationPackage まで明示しないと「set だ」エラーになる。
    NH_DARWIN_FLAKE = "${config.home.homeDirectory}/dotfiles/nix#darwinConfigurations.${user.username}";
    NH_HOME_FLAKE   = "${config.home.homeDirectory}/dotfiles/nix#homeConfigurations.${user.username}.activationPackage";
  };

  home.sessionPath = [
    "/opt/homebrew/bin"                         # brew 本体 (Apple Silicon)
    "/opt/homebrew/sbin"
    "${config.home.homeDirectory}/Library/pnpm"
    "${config.home.homeDirectory}/Library/pnpm/bin"
    "${config.home.homeDirectory}/.local/bin"  # uv tool 経由のバイナリ
    "${config.home.homeDirectory}/bin"          # home.file."bin/*" 経由のスクリプト
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

    plugins = [
      {
        # zsh の TAB 補完を fzf 化
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
      {
        # fish 風: Up/Down で先頭一致の履歴検索
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
      # ls エイリアスは programs.eza.enableZshIntegration で自動定義される
      tl = "textlint --config ~/.config/textlint/.textlintrc.json";
      tlf = "textlint --config ~/.config/textlint/.textlintrc.json --fix";
    };

    initContent = ''
      if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi

      # fish 風 setopt (移行時に失った機能の再現)
      setopt AUTO_CD              # ディレクトリ名タイプで cd 不要
      setopt AUTO_PUSHD           # cd 時に PUSHD (dirs スタックに積む)
      setopt PUSHD_IGNORE_DUPS    # 重複 push 除外
      setopt EXTENDED_HISTORY     # 履歴に timestamp 付与
      setopt GLOB_STAR_SHORT      # **/foo を **/foo に展開
      setopt INTERACTIVE_COMMENTS # 対話 shell で # コメント許可

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
      # 注: nh は自前 TUI 持ってるので alias 不要。nom は直接 nix build 用
      if command -v nom >/dev/null 2>&1; then
        alias nix-build='nix-build 2>&1 | nom'
        # nix build (CLI flake コマンド) は引数判定が必要なので関数化
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

      # gita: ghq 配下の全 repo を再登録 (新 repo を clone した後に呼ぶ)
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

  # 単発で使う CLI ツール群 (programs.* の対象外)
  home.packages = with pkgs; [
    comma                 # `, pkg args` で install せず nix package を実行
    nix-output-monitor    # nh / nix build を見やすくする (`nom`)
    nix-tree              # nix store 依存関係 TUI
    nix-init              # flake.nix 雛形生成
    devenv                # Nix ベース dev shell (direnv と組み合わせ)
    tealdeer              # tldr CLI (programs.tealdeer は archive_source 非対応のため手動)
    pngpaste              # obsidian.nvim / img-clip の macOS 画像貼付に必要
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
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      ghq.root = "${config.home.homeDirectory}/ghq";
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };
  };

  programs.bat = {
    enable = true;
    config = {
      style = "numbers,changes,header";
    };
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;  # ls/ll/la/lt alias 自動定義
    git = true;
    icons = "auto";
    extraOptions = [ "--group-directories-first" ];
  };

  # tealdeer: programs.tealdeer module は archive_source を知らないので、
  # package を直で入れて config.toml を手書きする
  home.file."Library/Application Support/tealdeer/config.toml".text = ''
    [updates]
    auto_update = true
    auto_update_interval_hours = 720
    archive_source = "https://github.com/tldr-pages/tldr/releases/latest/download/tldr.zip"
  '';

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

  # nh: darwin-rebuild / home-manager の便利ラッパー
  programs.nh = {
    enable = true;
    flake = "${config.home.homeDirectory}/dotfiles/nix";
  };

  # SOPS: 暗号化された secrets を home-manager switch 時に decrypt
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../secrets/secrets.yaml;
    secrets = {
      "vpn/proton".path     = "${config.home.homeDirectory}/.config/wireguard/proton.conf";
      "vpn/wgcf".path       = "${config.home.homeDirectory}/.config/wireguard/wgcf-profile.conf";
      "figma_token".path    = "${config.home.homeDirectory}/.figma_token";
      "claude_env".path     = "${config.home.homeDirectory}/.claude_env";
      "vault_token".path    = "${config.home.homeDirectory}/.vault-token";
      "rclone_conf".path    = "${config.home.homeDirectory}/.config/rclone/rclone.conf";
      "mcp_config".path     = "${config.home.homeDirectory}/.config/mcp/config.json";
      "espanso_match.yml".path  = "${config.home.homeDirectory}/Library/Application Support/espanso/match/base.yml";
      "calcurse_caldav_config".path = "${config.home.homeDirectory}/.config/calcurse/caldav/config";
      "ssh_config".path = "${config.home.homeDirectory}/.ssh/config";
      "aerc_accounts_conf".path = "${config.home.homeDirectory}/.config/aerc/accounts.conf";
    };
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
  home.file.".config/mpv" = {
    source = ../configs/media/mpv;
    recursive = true;
  };
  home.file.".config/launcher/config.toml".source = ../configs/launcher/config.toml;
  home.file."bin/nssh" = {
    source = ../configs/bin/nssh;
    executable = true;
  };
  home.file."bin/fzf-preview-repo" = {
    source = ../configs/bin/fzf-preview-repo;
    executable = true;
  };
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

  # macSKK / azooKey skkserv: sandboxed app の preferences
  # symlink 不可 (cfprefsd が nix store 経由の symlink chain を follow せず、
  # macSKK 側の plist write が dotfiles に届かない)。
  # → 起動毎に dotfiles から `defaults import` で適用する。
  # 設定 GUI で変更したら `just skk-export` で dotfiles に capture(後段で定義)。
  # 注: macSKK の Dictionary file 一覧は plist の dictionaries[] に persist されない
  #     ので、各 Mac で初回のみ手動で rm + ditto + toggle ON が必要(README 参照)。
  home.activation.skkPlistImport = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /usr/bin/defaults import net.mtgto.inputmethod.macSKK \
      ${../configs/ime/skk/macSKK.plist}
    if [ -f /Applications/azooKey\ skkserv.app/Contents/MacOS/azooKey\ skkserv ]; then
      /usr/bin/defaults import io.github.gitusp.azoo-key-skkserv \
        ${../configs/ime/skk/azoo-key-skkserv.plist}
    fi
    /usr/bin/killall cfprefsd 2>/dev/null || true
  '';


  # ログイン項目: ヘッドレス起動しない GUI 常駐アプリを auto-launch
  # (sketchybar/Karabiner は launchd plist で自動起動するので含めない)
  home.activation.macosLoginItems = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    LOGIN_APPS=(
      "/Applications/AeroSpace.app"
      "/Applications/Ghostty.app"
    )
    for app in "''${LOGIN_APPS[@]}"; do
      name=$(basename "$app" .app)
      if ! /usr/bin/osascript -e "tell application \"System Events\" to (name of login items) contains \"$name\"" 2>/dev/null | grep -q true; then
        /usr/bin/osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$app\", hidden:false}" >/dev/null 2>&1 || true
      fi
    done
  '';
}
