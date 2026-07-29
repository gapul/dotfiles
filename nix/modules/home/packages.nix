# Packages component (ECS: profile)。単発 CLI ツール群 (programs.* 対象外、OS 非依存)。
{
  pkgs,
  ...
}:
let
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
  git-wtpr = pkgs.callPackage ../../pkgs/git-wtpr.nix { };
in
{
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
    (callPackage ../../pkgs/tuicr.nix { }) # AI生成diffをPR風UIでレビュー
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
    tmux # ターミナルマルチプレクサ (zellij 代替。設定は modules/home/terminal.nix)
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
    (callPackage ../../pkgs/unity-cli.nix { }) # Unity Editor / module / project 管理 CLI
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
}
