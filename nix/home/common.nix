{
  config,
  pkgs,
  lib,
  user,
  ...
}:
let
  c = import ../lib/theme.nix; # アクティブテーマのパレット (切替は nix/lib/theme.nix の active)

  # zellij テーマ kdl を palette p から生成。dark/light 両方を吐き、config.kdl 側の
  # theme_dark / theme_light で端末パレット (= ghostty の macOS 追従) に連動させる。
  mkZellijTheme = name: p: ''
    themes {
        ${name} {
            fg "#${p.text}"
            bg "#${p.base}"
            black "#${p.overlay}"
            red "#${p.love}"
            green "#${p.foam}"
            yellow "#${p.gold}"
            blue "#${p.pine}"
            magenta "#${p.iris}"
            cyan "#${p.foam}"
            white "#${p.text}"
            orange "#${p.rose}"
        }
    }
  '';
in
{
  # OS 非依存の home-manager 設定
  # OS 固有の部分は home/darwin.nix / home/linux.nix / home/wsl.nix 等に分離

  home.username = user.username;
  home.stateVersion = "23.11";

  programs.home-manager.enable = true;

  # HM オプション docs (man home-configuration.nix / options.json) を生成しない。
  # switch 毎の 'options.json ... without proper context' warning を解消 + 微速化。
  # オプションは home-manager 公式 docs (オンライン) で参照する。
  manual.manpages.enable = false;
  manual.json.enable = false;

  # 静的 env vars は configs/shell/env-vars.json から読む (SSO、Win profile.ps1
  # と共有)。動的 path (HOME / XDG 依存) は下で個別に追加する。
  # $comment field は home.sessionVariables に渡せないので除外。
  home.sessionVariables =
    (lib.filterAttrs (n: _: n != "$comment") (
      builtins.fromJSON (builtins.readFile ../../configs/shell/env-vars.json)
    ))
    // {
      # ── 動的 path (HOME / XDG 依存、JSON 化不可) ──
      SOPS_AGE_KEY_FILE = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      CLAUDE_CONFIG_DIR = "${config.home.homeDirectory}/.config/claude";

      # XDG Base Directory: 実行時に $XDG_* を参照する CLI 向けに明示 export
      # (home-manager はビルド時に config.xdg.* を展開するだけで env には出さないため)
      XDG_CONFIG_HOME = config.xdg.configHome;
      XDG_DATA_HOME = config.xdg.dataHome;
      XDG_STATE_HOME = config.xdg.stateHome;
      XDG_CACHE_HOME = config.xdg.cacheHome;

      # cargo / npm / bundler を XDG 配下に
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
      NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/npmrc";
      BUNDLE_USER_CONFIG = "${config.xdg.configHome}/bundle/config";
      BUNDLE_USER_CACHE = "${config.xdg.cacheHome}/bundle";
      BUNDLE_USER_PLUGIN = "${config.xdg.dataHome}/bundle/plugin";
    };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin" # uv tool 経由のバイナリ
    "${config.home.homeDirectory}/bin" # home.file."bin/*" 経由のスクリプト
    "${config.xdg.dataHome}/cargo/bin" # cargo install のバイナリ (CARGO_HOME/bin)
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
        # nix-daemon.sh は ~/.nix-profile と新 profile が両方あると
        # "safely delete either" 警告を stderr に出す。両 symlink は意図的に
        # 残すので、警告だけ握りつぶす (export は source なので全て残る)。
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null
      fi
      [ -f "$HOME/.local/state/nix/profile/etc/profile.d/hm-session-vars.sh" ] && \
        . "$HOME/.local/state/nix/profile/etc/profile.d/hm-session-vars.sh"
    '';
  };

  # login(1) の "Last login: ..." 行を抑止 (macOS 標準挙動・非破壊)。
  home.file.".hushlogin".text = "";

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh"; # XDG: zsh設定一式を ~/.config/zsh/ へ (ZDOTDIR)。HM 26.05 は絶対パス必須

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
      cfw = "~/Developer/github.com/gapul/personal-tools/cloudflare/bin/cf-wrangler";
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

      # jd (just-dotfiles): dotfiles の just レシピをどこからでも実行 (cd 不要)。
      #   例: jd rebuild / jd update / jd (引数なしで一覧)
      #   nh は NH_*_FLAKE で flake を env 指定済みなので cwd 非依存。
      #   --working-directory で justfile_directory() 依存レシピ (sketchybar-font 等) も正しく動く。
      function jd() {
        just --justfile "$HOME/.dotfiles/Justfile" --working-directory "$HOME/.dotfiles" "$@"
      }

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

  # 単発で使う CLI ツール群 (programs.* の対象外、OS 非依存)
  home.packages = with pkgs; [
    comma # `, pkg args` で install せず nix package を実行
    nix-output-monitor # nh / nix build を見やすくする (`nom`)
    nix-tree # nix store 依存関係 TUI
    nix-init # flake.nix 雛形生成
    devenv # Nix ベース dev shell (direnv と組み合わせ)
    tealdeer # tldr CLI (programs.tealdeer は archive_source 非対応のため手動)

    # ─── Homebrew から移行した CLI (段階1: git周辺 + 基本) ───
    gh # GitHub CLI
    ghq # repo クローン管理
    lazyjj # jujutsu TUI
    jq # JSON プロセッサ
    fd # find 代替 (fzf defaultCommand でも使用)
    just # コマンドランナー (この Justfile を実行)
    bottom # システムモニタ (btm)
    dust # ディスク使用量 (旧 du-dust)
    ncdu # ディスク使用量 TUI
    yazi # ファイルマネージャ TUI
    zellij # ターミナルマルチプレクサ

    # ─── Homebrew から移行した CLI (段階2: build/言語/文書/security/network) ───
    cmake # ビルドシステム
    meson # ビルドシステム
    tree-sitter # 旧 tree-sitter-cli
    uv # Python パッケージ管理
    pnpm # Node パッケージ管理
    pandoc # ドキュメント変換
    typst # 組版
    poppler-utils # PDF CLI (pdftotext 等。旧 brew poppler)
    imagemagick # 画像変換 (magick)
    libsixel # sixel (img2sixel)
    bitwarden-cli # Bitwarden (bw)
    syft # SBOM
    radare2 # リバースエンジニアリング (r2)
    age # SOPS 暗号化バックエンド
    sops # secrets 管理
    gitleaks # pre-commit の機密 leak 検査
    pre-commit # hook framework
    aria2 # ダウンローダ (aria2c)
    rclone # クラウドストレージ同期
    opencode # AI コーディング CLI
    glow # markdown ビューア
    chafa # 画像→ターミナル
    w3m # テキストブラウザ
    calcurse # カレンダー TUI

    # ─── cargo/uv からローカル install していたものを nix 宣言化 (再現性確保) ───
    cargo-cache # cargo build artifacts 掃除 (just gc が依存)
    youtube-tui # YouTube TUI
    gita # マルチリポ git 管理 (~/.config/gita)
    compiledb # compile_commands.json 生成

    # ─── Homebrew から移行した CLI (段階3) ───
    # rust: rustup でなく rustc+cargo (固定版・宣言的)。nightly/toolchain切替が要る場合は rustup へ
    rustc # Rust コンパイラ
    cargo # Rust ビルド/パッケージ管理
    docker-compose # コンテナ compose (podman socket を向ける)
    podman # コンテナ (machine VM は別管理で維持)
    fontforge # フォント編集 CLI (GUI は fontforge-app cask)
    python3Packages.fonttools # フォント操作 lib/CLI
    ollama # ローカル LLM (nix 版も Metal GPU 有効 — runner が Metal.framework をリンク。検証済)
    neovim # エディタ本体 (設定は configs/editors/nvim を mkOutOfStoreSymlink)
    aerc # メール TUI
    isync # IMAP 同期 (mbsync)

    # ─── yazi プレビュー用 (piper 経由 or 内蔵 previewer が利用) ───
    ffmpegthumbnailer # 動画サムネイル (yazi 内蔵 video previewer が使用)
    ouch # 書庫(zip/tar/7z 等)の中身一覧/展開
    rich-cli # csv/json/md 等のリッチ整形 (piper previewer から呼ぶ)

    # ─── lint/format 一元管理 (CLI・Neovim・CI で同一バイナリ/同一版に統一) ───
    # Neovim(conform/nvim-lint)は PATH 上のこれらを参照する。Mason 側では
    # ensure_installed から除外し二重管理を排除 (configs/editors/nvim/lua/plugins/tooling.lua)。
    stylua # Lua 整形
    shfmt # Shell 整形
    prettier # js/ts/json/yaml/css/md 整形
    ruff # Python lint + format
    markdownlint-cli2 # Markdown lint
    # 日本語校閲 textlint (ルール一式を buildNpmPackage で固定。pnpm global を廃止)
    (callPackage ../pkgs/textlint-ja.nix { })
  ];

  programs.git = {
    enable = true;
    ignores = [
      # macOS が各フォルダに撒くメタデータ (ノイズ。リポジトリに不要)
      ".DS_Store"
      ".DS_Store?"
      "._*" # AppleDouble (リソースフォーク)
      ".AppleDouble"
      ".LSOverride"
      ".Spotlight-V100"
      ".Trashes"
      ".fseventsd"
      ".DocumentRevisions-V100"
      ".TemporaryItems"
      ".VolumeIcon.icns"
      ".com.apple.timemachine.donotpresent"
      ".apdisk"
      "Thumbs.db" # Windows
      ".idea/"
      ".vscode/"
      "*.swp"
      "*.swo"
      ".direnv/"
      "result"
      "result-*"
      ".envrc.local"
      ".claude/settings.local.json"
      # LaTeX ビルド中間生成物 (latexmk / lualatex)
      "*.aux"
      "*.fdb_latexmk"
      "*.fls"
      "*.log"
      "*.out"
      "*.toc"
      "*.synctex.gz"
      "*.bbl"
      "*.bcf"
      "*.run.xml"
      "*.nav"
      "*.snm"
      "*.vrb"
    ];
    signing = {
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    # HM 26.05: userName/userEmail/extraConfig は settings.* に統合
    settings = {
      user.name = user.gitUser;
      user.email = user.gitEmail;
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      ghq.root = "${config.home.homeDirectory}/Developer";
      merge.conflictstyle = "diff3";
      # flake.lock 自動解決 driver (.gitattributes の `nix/flake.lock merge=flakelock`)。
      # Mac/Lab PC 両機の nix flake update 競合を、片側採用(常に valid な lock)で無人解決。
      # 入力差を厳密に揃えたい時は解決後 `nix flake update` を一度回す。
      merge.flakelock.name = "flake.lock auto-resolve";
      merge.flakelock.driver = "cp -f %B %A";
      diff.colorMoved = "default";
      gpg.format = "ssh";
      "gpg \"ssh\"".allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";
    };
  };

  # HM 26.05: programs.git.delta → 独立した programs.delta へ移行
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = true;
      syntax-theme = "rose-pine"; # bat の rose-pine テーマを使用 (テーマ統一)
      detect-dark-light = "auto"; # 端末の明暗を検出し diff 配色を macOS 外観に追従
    };
  };

  programs.bat = {
    enable = true;
    config = {
      style = "numbers,changes,header";
      # macOS 外観に自動追従。dark=rose-pine / light=rose-pine-dawn。
      theme = "auto:system";
      theme-dark = "rose-pine";
      theme-light = "rose-pine-dawn";
    };
    # Rosé Pine tmTheme を vendor (bat cache に登録される)。dawn は dark を hex 置換で生成。
    themes."rose-pine" = {
      src = ../../configs/cli/bat/themes;
      file = "rose-pine.tmTheme";
    };
    themes."rose-pine-dawn" = {
      src = ../../configs/cli/bat/themes;
      file = "rose-pine-dawn.tmTheme";
    };
  };

  # lazygit: ANSI 名前色で端末パレットに乗せ、ghostty の macOS 外観追従に連動させる。
  # (固定 hex をやめたぶん色精度は端末の 16 色に丸まるが dark/light 自動切替になる)
  programs.lazygit = {
    enable = true;
    settings.gui.theme = {
      activeBorderColor = [
        "magenta" # iris 相当
        "bold"
      ];
      inactiveBorderColor = [ "blue" ]; # pine 相当
      optionsTextColor = [ "cyan" ]; # foam 相当
      selectedLineBgColor = [ "blue" ];
      cherryPickedCommitBgColor = [ "magenta" ];
      cherryPickedCommitFgColor = [ "blue" ];
      unstagedChangesColor = [ "red" ]; # love 相当
      defaultFgColor = [ "default" ];
    };
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
    # 端末の 16 色 ANSI を継承 → ghostty の Rose Pine / Rose Pine Dawn (macOS 外観追従)
    # に自動で乗る。固定 hex をやめることで dark/light 自動切替に対応。
    defaultOptions = [ "--color=16" ];
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
      filter_mode = "global"; # 全 host 横断検索
      style = "compact";
      inline_height = 20;
      enter_accept = false; # Enter で実行せず編集に
      show_preview = true;
      # TUI デバッグログ(~/.atuin/logs)を抑止し home 直下を汚さない。
      # config/data は既に XDG (~/.config/atuin, ~/.local/share/atuin)。
      logs.enabled = false;
      # 明示テーマは付けず端末のデフォルト配色を使う → ghostty の macOS 外観追従に連動。
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
    flake = "${config.home.homeDirectory}/.dotfiles/nix";
  };

  # SOPS: 暗号化された secrets を home-manager switch 時に decrypt
  # (path に ~/Library が無いものは OS 非依存)
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/secrets.yaml;
    secrets = {
      "vpn/proton".path = "${config.home.homeDirectory}/.config/wireguard/proton.conf";
      "vpn/wgcf".path = "${config.home.homeDirectory}/.config/wireguard/wgcf-profile.conf";
      "rclone_conf".path = "${config.home.homeDirectory}/.config/rclone/rclone.conf";
      "ssh_config".path = "${config.home.homeDirectory}/.ssh/config";

      # PII 単一ソース
      "pii/name" = { };
      "pii/email_personal" = { };
      "pii/email_school" = { };
      "pii/email_work" = { };
      "pii/gmail_app_password_mail" = { };
      "pii/gmail_app_password_caldav" = { };
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
  # zellij テーマは nix/lib/rose-pine.nix から生成 (config.kdl は theme "rose-pine" で参照)
  home.file.".config/zellij/themes/rose-pine.kdl".text = mkZellijTheme "rose-pine" c.dark;
  home.file.".config/zellij/themes/rose-pine-dawn.kdl".text = mkZellijTheme "rose-pine-dawn" c.light;
  # supermaven: sm-agent は $HOME/.supermaven をハードコード参照 (XDG 非対応)。
  # 実体は ~/.local/share/supermaven に置き、$HOME はそこへの symlink にして両立。
  # (丸ごと移動すると agent が config を見失い認証ロストするため symlink が必須)
  home.file.".supermaven".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/supermaven";

  # bday: 自作 birthday-tui のランチャ。ghq(~/Developer) の checkout を PATH に通す。
  # nvim 側は lazy dev で同 checkout を読む (configs/editors/nvim/lua/config/lazy.lua)。
  home.file.".local/bin/bday".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Developer/github.com/gapul/birthday-tui/bday";

  home.file.".config/starship.toml".source = ../../configs/shell/starship.toml;
  home.file.".config/gh/config.yml".source = ../../configs/cli/gh/config.yml;
  home.file.".config/textlint" = {
    source = ../../configs/textlint;
    recursive = true;
  };
  # LaTeX: latexmk 既定設定 (LuaLaTeX) と日本語テンプレート
  home.file.".latexmkrc".source = ../../configs/tex/latexmkrc;
  home.file.".config/tex/templates" = {
    source = ../../configs/tex/templates;
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
  home.file.".config/calcurse" = {
    source = ../../configs/cli/calcurse;
    recursive = true;
  };

  # nvim は dotfiles に直接書き戻したいので mkOutOfStoreSymlink
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/editors/nvim";

  # Zed: settings.json のみ管理 (UI 編集が repo に直書きされるよう mkOutOfStoreSymlink)。
  # 他の ~/.config/zed/* は会話履歴等の state なので触らない。
  home.file.".config/zed/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/editors/zed/settings.json";
}
