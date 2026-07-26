{
  config,
  pkgs,
  lib,
  ...
}:
{
  # workstation 層: 母艦 (laptop) / WSL / linux 用の開発・生活ツール。
  # macmini (ヘッドレス AI ノード) はこれを積まない (common.nix から分離 2026-07-19)。

  home.packages = with pkgs; [
    pandoc # ドキュメント変換
    typst # 組版
    # 日本語の学術文書に必要な TeX Live コレクションを Nix で合成する。
    # scheme-full は避けつつ、数式・図表・参考文献・一般的な追加パッケージを
    # 個別追加なしで利用できる範囲を揃える。
    (texlive.combine {
      inherit (texlive)
        scheme-medium
        latexmk
        collection-langjapanese
        collection-latexextra
        collection-mathscience
        collection-bibtexextra
        collection-fontsrecommended
        ;
    })
    poppler-utils # PDF CLI (pdftotext 等。旧 brew poppler)
    bitwarden-cli # Bitwarden (bw)
    syft # SBOM
    radare2 # リバースエンジニアリング (r2)
    aria2 # ダウンローダ (aria2c)
    rclone # クラウドストレージ同期
    calcurse # カレンダー TUI
    cargo-cache # cargo build artifacts 掃除 (just gc が依存)
    youtube-tui # YouTube TUI
    gita # マルチリポ git 管理 (~/.config/gita)
    compiledb # compile_commands.json 生成
    cmake # ビルドシステム
    meson # ビルドシステム
    tree-sitter # 旧 tree-sitter-cli
    # rust: rustup でなく rustc+cargo (固定版・宣言的)。nightly/toolchain切替が要る場合は rustup へ
    rustc # Rust コンパイラ
    cargo # Rust ビルド/パッケージ管理
    docker-compose # コンテナ compose (podman socket を向ける)
    podman # コンテナ (machine VM は別管理で維持)
    fontforge # フォント編集 CLI (GUI は fontforge-app cask)
    python3Packages.fonttools # フォント操作 lib/CLI
    aerc # メール TUI
    isync # IMAP 同期 (mbsync)
    # 日本語校閲 textlint (ルール一式を buildNpmPackage で固定。pnpm global を廃止)
    (callPackage ../pkgs/textlint-ja.nix { })
  ];

  # ユーザーデータ置き場 (Google Drive mount / Syncthing 共有)
  home.activation.workstationDataDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p \
      "${config.home.homeDirectory}/Cloud" \
      "${config.home.homeDirectory}/Sync"
  '';

  # codex / claude: env (CODEX_HOME / CLAUDE_CONFIG_DIR) を読まない起動経路
  # (CodexBar 等の GUI アプリ、popo の env 無し spawn) が ~/.codex ~/.claude を
  # 再生成して分裂するため、XDG 実体への symlink にしてどの経路でも同じ場所に
  # 収束させる (.supermaven と同じ手法)。
  home.file.".codex".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/codex";
  home.file.".claude".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/claude";

  # supermaven: sm-agent は $HOME/.supermaven をハードコード参照 (XDG 非対応)。
  # 実体は ~/.local/share/supermaven に置き、$HOME はそこへの symlink にして両立。
  # (丸ごと移動すると agent が config を見失い認証ロストするため symlink が必須)
  home.file.".supermaven".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/supermaven";

  # bday: 自作 birthday-tui のランチャ。ghq(~/Developer) の checkout を PATH に通す。
  # nvim 側は lazy dev で同 checkout を読む (configs/editors/nvim/lua/config/lazy.lua)。
  home.file.".local/bin/bday".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Developer/github.com/gapul/birthday-tui/bday";

  home.file.".config/textlint" = {
    source = ../../configs/textlint;
    recursive = true;
  };
  # LaTeX: latexmk 既定設定 (LuaLaTeX) と日本語テンプレート
  # latexmk 4.77+ は $XDG_CONFIG_HOME/latexmk/latexmkrc を公式サポートするため XDG 準拠の配置にする
  home.file.".config/latexmk/latexmkrc".source = ../../configs/tex/latexmkrc;
  home.file.".config/tex/templates" = {
    source = ../../configs/tex/templates;
    recursive = true;
  };
  home.file.".config/mpv" = {
    source = ../../configs/media/mpv;
    recursive = true;
  };
  # uosc は vendored (ziggy バイナリ 18MB 同梱) をやめ nixpkgs から供給。
  # 第三者バイナリを repo に抱えない構造にする (ziggy 依存の DL 機能は未使用)。
  home.file.".config/mpv/scripts/uosc".source = "${pkgs.mpvScripts.uosc}/share/mpv/scripts/uosc";
  home.file.".config/launcher/config.toml".source = ../../configs/launcher/config.toml;
  home.file.".config/calcurse" = {
    source = ../../configs/cli/calcurse;
    recursive = true;
  };

  # Zed: settings.json のみ管理 (UI 編集が repo に直書きされるよう mkOutOfStoreSymlink)。
  # 他の ~/.config/zed/* は会話履歴等の state なので触らない。
  home.file.".config/zed/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/editors/zed/settings.json";
}
