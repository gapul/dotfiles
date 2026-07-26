{
  config,
  pkgs,
  lib,
  user,
  nixIndexDatabase,
  agentSkills,
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

  gh-nix = pkgs.writeShellApplication {
    name = "gh-nix";
    runtimeInputs = [ pkgs.gh ];
    text = ''
      if [ "$#" -eq 0 ]; then
        echo "usage: gh-nix <command> [args...]" >&2
        exit 2
      fi
      if ! gh auth status >/dev/null 2>&1; then
        echo "gh-nix: run 'gh auth login' first" >&2
        exit 1
      fi
      token="$(gh auth token)"
      exec env NIX_CONFIG="access-tokens = github.com=$token
      ''${NIX_CONFIG:-}" "$@"
    '';
  };
  lazyNixPlugins =
    pkgs.linkFarm "lazy-nix-plugins"
      (import ../../configs/editors/nvim/lazy2nix { inherit pkgs lib; }).plugins;
  git-wtpr = pkgs.callPackage ../pkgs/git-wtpr.nix { };
in
{
  imports = [
    nixIndexDatabase.homeModules.default
    agentSkills.homeManagerModules.default
    ../modules/home/git.nix
    ../modules/home/cli.nix
    ../modules/home/nix-tools.nix
    ../modules/home/shell.nix
  ];

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
      CODEX_HOME = "${config.xdg.dataHome}/codex";
      CODEX_SQLITE_HOME = "${config.xdg.stateHome}/codex/sqlite";
      LAZY_NIX_PLUGINS = lazyNixPlugins;

      # XDG Base Directory: 実行時に $XDG_* を参照する CLI 向けに明示 export
      # (home-manager はビルド時に config.xdg.* を展開するだけで env には出さないため)
      XDG_CONFIG_HOME = config.xdg.configHome;
      XDG_DATA_HOME = config.xdg.dataHome;
      XDG_STATE_HOME = config.xdg.stateHome;
      XDG_CACHE_HOME = config.xdg.cacheHome;

      # GnuPG: 既定の ~/.gnupg を $XDG_DATA_HOME/gnupg へ。上流は XDG 非対応のため
      # GNUPGHOME で明示。dir perms は 700 必須 (移設時に chmod 済み)。
      GNUPGHOME = "${config.xdg.dataHome}/gnupg";

      # cargo / bundler を XDG 配下に
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      BUNDLE_USER_CONFIG = "${config.xdg.configHome}/bundle/config";
      BUNDLE_USER_CACHE = "${config.xdg.cacheHome}/bundle";
      BUNDLE_USER_PLUGIN = "${config.xdg.dataHome}/bundle/plugin";

      # npm: 上流既定の ~/.npmrc / ~/.npm / ~/.npm-global 相当を XDG 配下へ寄せる。
      NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/npmrc";
      NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
      NPM_CONFIG_PREFIX = "${config.xdg.dataHome}/npm";

      # PlatformIO: 既定の ~/.platformio (toolchain 等で GB 級) を XDG data へ。
      PLATFORMIO_CORE_DIR = "${config.xdg.dataHome}/platformio";
      # Dart/Flutter: pub パッケージキャッシュ ~/.pub-cache を XDG cache へ (再取得可能)。
      PUB_CACHE = "${config.xdg.cacheHome}/pub";
      # matplotlib: macOS では XDG 非対応のため MPLCONFIGDIR で明示。
      MPLCONFIGDIR = "${config.xdg.configHome}/matplotlib";
    };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin" # uv tool 経由のバイナリ
    "${config.home.homeDirectory}/bin" # home.file."bin/*" 経由のスクリプト
    "${config.xdg.dataHome}/cargo/bin" # cargo install のバイナリ (CARGO_HOME/bin)
    "${config.xdg.dataHome}/npm/bin" # npm install -g のバイナリ (NPM_CONFIG_PREFIX/bin)
  ];

  # pnpm グローバル設定 (pnpm 11+ は YAML)。NPM_CONFIG_USERCONFIG とは別系統。
  # サプライチェーン対策: 公開14日(20160分)未満のバージョンは取得しない。
  # 緊急時のみ: pnpm install --config.minimumReleaseAge=0
  xdg.configFile."pnpm/config.yaml".text = ''
    minimumReleaseAge: 20160
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
      # Codex は XDG を直接分割参照しないため、公式の CODEX_HOME で
      # ~/.codex から XDG data/state 配下へ寄せる。
      export CODEX_HOME="$HOME/.local/share/codex"
      export CODEX_SQLITE_HOME="$HOME/.local/state/codex/sqlite"
      # HISTFILE も .zshrc を読まない古い/GUI 起動シェルが ~/.zsh_history へ
      # 漏らさないよう、ガード無しの .zshenv で XDG パスを先に固定しておく。
      export HISTFILE="$HOME/.local/state/zsh/history"
      # GNUPGHOME も同様。未設定の zsh から gpg を叩くと空の ~/.gnupg を
      # 再生成してしまうため、ガード無しの .zshenv で先に固定しておく。
      export GNUPGHOME="$HOME/.local/share/gnupg"
      # npm も XDG 非対応の既定 (~/.npmrc / ~/.npm) を環境変数で固定する。
      export NPM_CONFIG_USERCONFIG="$HOME/.config/npm/npmrc"
      export NPM_CONFIG_CACHE="$HOME/.cache/npm"
      export NPM_CONFIG_PREFIX="$HOME/.local/share/npm"
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

  # ユーザーが直接扱う同期/クラウドデータの置き場。
  # XDG は app config/cache/state 向けなので、Google Drive mount や Syncthing
  # 共有フォルダのような user data は HOME 直下のカテゴリにまとめる。
  home.activation.userDataDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p \
      "${config.xdg.dataHome}/codex" \
      "${config.xdg.stateHome}/codex/sqlite" \
      "${config.xdg.configHome}/npm" \
      "${config.xdg.cacheHome}/npm" \
      "${config.xdg.dataHome}/npm"
  '';

  # 単発で使う CLI ツール群 (programs.* の対象外、OS 非依存)
  home.packages = with pkgs; [
    nixd # Nix LSP (Neovim から利用)
    gh-nix # gh の認証を一時的に Nix access-tokens へ橋渡し
    nix-output-monitor # nh / nix build を見やすくする (`nom`)
    nix-tree # nix store 依存関係 TUI
    nix-init # flake.nix 雛形生成
    nvd # Nix / Home Manager generation のパッケージ差分
    optnix # NixOS / Home Manager / nix-darwin option 検索 TUI
    devenv # Nix ベース dev shell (direnv と組み合わせ)
    tealdeer # tldr CLI (programs.tealdeer は archive_source 非対応のため手動)

    # ─── Homebrew から移行した CLI (段階1: git周辺 + 基本) ───
    gh # GitHub CLI
    gh-dash # GitHub PR / Issue ダッシュボード TUI
    git-wt # worktree作成・切替・安全削除を`git wt`へ統一
    git-wtpr # `git wtpr <PR番号|URL>`でPR専用worktreeへ移動
    trash-cli # git-wtの削除をゴミ箱経由にする
    tirith # shell/AI agent向けcommand・URL・Skill防御
    (callPackage ../pkgs/tuicr.nix { }) # AI生成diffをPR風UIでレビュー
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
    podman-tui # Podman コンテナ / イメージ / Pod 管理 TUI
    iamb # Matrix TUI (Vim キーバインド、E2EE 対応)
    newsboat # RSS/Atom フィードリーダー TUI
    presenterm # Markdown プレゼンテーション TUI
    termshark # tshark/Wireshark のパケット解析 TUI

    # ─── Homebrew から移行した CLI (段階2: build/言語/文書/security/network) ───
    uv # Python パッケージ管理
    pnpm # Node パッケージ管理
    imagemagick # 画像変換 (magick)
    libsixel # sixel (img2sixel)
    age # SOPS 暗号化バックエンド
    sops # secrets 管理
    gitleaks # pre-commit の機密 leak 検査
    pre-commit # hook framework
    opencode # AI コーディング CLI
    (callPackage ../pkgs/unity-cli.nix { }) # Unity Editor / module / project 管理 CLI
    glow # markdown ビューア
    chafa # 画像→ターミナル
    ddgr # DuckDuckGo 対話型ターミナル検索
    w3m # テキストブラウザ

    # ─── cargo/uv からローカル install していたものを nix 宣言化 (再現性確保) ───

    # ─── Homebrew から移行した CLI (段階3) ───
    ollama # ローカル LLM (nix 版も Metal GPU 有効 — runner が Metal.framework をリンク。検証済)
    neovim # エディタ本体 (設定は configs/editors/nvim を mkOutOfStoreSymlink)

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
  ];

  # SOPS 定義は home/secrets.nix へ分離 (age 鍵を持たない macmini が
  # common.nix を共有できるようにするため。2026-07-19)

  # Ghostty の terminfo を全ホストへ配布。ssh 先で TERM=xterm-ghostty が未知だと
  # ZLE が端末能力を誤解して入力が壊れる (macmini で実害あり 2026-07-19)。
  # pkgs.ghostty は darwin unsupported のため infocmp ダンプを vendoring して
  # activation 時に tic でコンパイルする。
  home.activation.ghosttyTerminfo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.ncurses}/bin/tic -x -o "$HOME/.terminfo" ${../../configs/terminals/ghostty/xterm-ghostty.terminfo}
  '';

  # dotfiles/configs/* を symlink (OS 非依存なものだけ。Mac 専用 = aerospace/sketchybar/karabiner は home/darwin.nix へ)
  home.file.".config/zellij" = {
    source = ../../configs/terminals/zellij;
    recursive = true;
  };
  # zellij テーマは nix/lib/rose-pine.nix から生成 (config.kdl は theme "rose-pine" で参照)
  home.file.".config/zellij/themes/rose-pine.kdl".text = mkZellijTheme "rose-pine" c.dark;
  home.file.".config/zellij/themes/rose-pine-dawn.kdl".text = mkZellijTheme "rose-pine-dawn" c.light;
  home.file.".config/starship.toml".source = ../../configs/shell/starship.toml;
  home.file.".config/gh/config.yml".source = ../../configs/cli/gh/config.yml;
  # markdownlint-cli2: 親方向探索でホーム以下全 Markdown の既定になるため、
  # XDG 非対応だがホーム直下がツールの仕様上正しい置き場所。
  home.file.".markdownlint-cli2.jsonc".source =
    ../../configs/cli/markdownlint/markdownlint-cli2.jsonc;
  # Codex: 上流は ~/.codex 既定だが、CODEX_HOME で XDG data 配下へ移す。
  # auth/history/skills/plugins は CODEX_HOME、SQLite は CODEX_SQLITE_HOME に分離。
  # TUI から設定が更新されても repo に反映されるよう out-of-store symlink にする。
  xdg.dataFile."codex/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/cli/codex/config.toml";
  xdg.dataFile."codex/themes/rose-pine.tmTheme".source =
    ../../configs/cli/bat/themes/rose-pine.tmTheme;
  xdg.dataFile."codex/themes/rose-pine-dawn.tmTheme".source =
    ../../configs/cli/bat/themes/rose-pine-dawn.tmTheme;
  # 素の Vim: native XDG で読まれる vimrc。.viminfo を $XDG_STATE_HOME へ追い出す目的
  home.file.".config/vim/vimrc".source = ../../configs/editors/vim/vimrc;
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
  # nvim は dotfiles に直接書き戻したいので mkOutOfStoreSymlink
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/editors/nvim";

  # Native Messaging manifest は仕様上 launcher の絶対パスを要求し、Firenvim の
  # launcher 自体も install 時の HOME/XDG/PATH を埋め込む。ユーザー名や home を
  # 移行しても古いパスを保持しないよう、HM 適用時に現在の環境から再生成する。
  home.activation.firenvimNativeMessaging = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -d "${config.xdg.dataHome}/nvim/lazy/firenvim" ]; then
      run ${pkgs.neovim}/bin/nvim --headless \
        "+call firenvim#install(0)" \
        "+qa"
    fi
  '';

}
