{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Search binary for the ghostty launcher. Store-ify it to protect it from gc-deep's target cleanup.
  launcher-search = pkgs.callPackage ../pkgs/launcher-search.nix { };
  claudeConfig =
    path:
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/cli/claude/${path}";
in
{
  # workstation layer: dev/daily tools for the main machine (laptop) / WSL / linux.
  # macmini (headless AI node) doesn't load this (split from common.nix 2026-07-19).

  home.packages = with pkgs; [
    launcher-search # ghostty launcher search backend (replaces core/launcher-search)
    pandoc # document conversion
    typst # typesetting
    # Compose the TeX Live collections needed for Japanese academic documents via Nix.
    # Avoid scheme-full while covering math, figures/tables, bibliographies, and common
    # extra packages without adding them individually.
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
    poppler-utils # PDF CLI (pdftotext etc. formerly brew poppler)
    bitwarden-cli # Bitwarden (bw)
    syft # SBOM
    radare2 # reverse engineering (r2), small native binaries (e.g. REAPER)
    # app / binary analysis: unofficial-client recon + Mac proprietary-app RE
    jadx # APK: dex -> readable Java
    apktool # APK: resources + AndroidManifest decode
    apkeep # APK/XAPK downloader (Play / APKPure)
    asar # extract Electron app.asar (e.g. Native Access)
    cfr # JVM decompiler (e.g. Bitwig jars)
    ghidra # native Mach-O/ELF reverse engineering (GUI)
    aria2 # downloader (aria2c)
    rclone # cloud storage sync
    calcurse # calendar TUI
    cargo-cache # clean cargo build artifacts (just gc depends on it)
    youtube-tui # YouTube TUI
    gita # multi-repo git management (~/.config/gita)
    compiledb # generate compile_commands.json
    cmake # build system
    meson # build system
    tree-sitter # formerly tree-sitter-cli
    # rust: rustc+cargo instead of rustup (pinned, declarative). Use rustup if you need nightly/toolchain switching
    rustc # Rust compiler
    cargo # Rust build/package management
    docker-compose # container compose (points at the podman socket)
    podman # containers (the machine VM is maintained separately)
    fontforge # font editing CLI (GUI is the fontforge-app cask)
    python3Packages.fonttools # font manipulation lib/CLI
    stockfish # chess engine, spoken to over UCI (the Puddle chess wallpaper's opponent)
    aerc # mail TUI
    isync # IMAP sync (mbsync)
    # Japanese proofreading textlint (whole ruleset pinned via buildNpmPackage; pnpm global retired)
    (callPackage ../pkgs/textlint-ja.nix { })
  ];

  # User data location: everything that also lives somewhere else sits under ~/Sync (2026-08).
  # google-drive-* are rclone mounts (remote-primary, see home/rclone-mount.nix), syncthing holds
  # real local files (local-primary, the only one restic backs up).
  home.activation.workstationDataDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p \
      "${config.home.homeDirectory}/Sync/google-drive-personal" \
      "${config.home.homeDirectory}/Sync/google-drive-school" \
      "${config.home.homeDirectory}/Sync/syncthing"
  '';

  # codex / claude: launch paths that don't read the env (CODEX_HOME / CLAUDE_CONFIG_DIR)
  # (GUI apps like CodexBar, popo's env-less spawn) regenerate ~/.codex ~/.claude and
  # cause a split, so symlink them to the XDG entities so every path converges on the
  # same location (same technique as .supermaven).
  home.file.".codex".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/codex";
  home.file.".claude".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/claude";

  # Claude Code: CLAUDE_CONFIG_DIR mixes config with state (sessions/history/.claude.json hold
  # credentials), so only the hand-written parts are linked in. Out-of-store symlinks, so edits
  # made from the TUI (/config, skill authoring) land back in the repo.
  # Vendored skills (cloudflare/*, wrangler, humanizer-ja, ...) stay unmanaged: they are
  # re-installable from upstream. Workstation-only because the hooks are desktop-specific
  # (osascript notifications, herdr) — move this to modules/home/agents.nix to share it.
  xdg.configFile = {
    "claude/settings.json".source = claudeConfig "settings.json";
    "claude/CLAUDE.md".source = claudeConfig "CLAUDE.md";
    "claude/hooks".source = claudeConfig "hooks";
    "claude/output-styles".source = claudeConfig "output-styles";
    "claude/bin".source = claudeConfig "bin";
    "claude/skills/english-vocab".source = claudeConfig "skills/english-vocab";
    "claude/skills/gapul-writing-voice".source = claudeConfig "skills/gapul-writing-voice";
    "claude/skills/step-by-step-tutor".source = claudeConfig "skills/step-by-step-tutor";
  };

  # supermaven: sm-agent hardcodes $HOME/.supermaven (not XDG-aware).
  # Keep the real dir at ~/.local/share/supermaven and make $HOME a symlink to it.
  # (Moving it wholesale makes the agent lose its config and its auth, so the symlink is required)
  home.file.".supermaven".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/supermaven";

  # bday: launcher for the homemade birthday-tui. Puts the ghq (~/Developer) checkout on PATH.
  # nvim reads the same checkout via lazy dev (configs/editors/nvim/lua/config/lazy.lua).
  home.file.".local/bin/bday".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Developer/github.com/gapul/birthday-tui/bday";

  home.file.".config/textlint" = {
    source = ../../configs/textlint;
    recursive = true;
  };
  # prh's WEB+DB PRESS rules: someone else's dictionary, fetched rather than copied in.
  # `.textlintrc.json` names it by the relative path it lands at, so nothing there changes.
  home.file.".config/textlint/prh/web-db-press.yml".source = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/prh/rules/89a6f9dd057a34dce15698260ced88183e332362/media/WEB%2BDB_PRESS.yml";
    hash = "sha256-6RTk8Qs/ZVG71vp7kYhu81CCh3uJwsRYk6ER09DMQVw=";
  };
  # HPI (Human Programming Interface)。SaaS から引き出したエクスポートを、
  # ローカルで横断的に引ける形にしておくための枠組み。
  #
  # `~/.config/my` が my.config パッケージとして読まれる。HPI 側の
  # my/core/init.py が MY_CONFIG (既定は platformdirs の user_config_dir) を
  # sys.path の先頭に差し込むので、ここに置いたファイルは implicit namespace
  # package として `my.*` で import できる。__init__.py は要らない (PEP 420)。
  #
  # activitywatch.py と atuin.py は上流に存在しないので自前。ActivityWatch は
  # この環境で一番量のあるローカルデータ (実測 115 万イベント) なのに、HPI が
  # 持っているのは arbtt と rescuetime だけだった。atuin も同様に無い。
  # 前者は「Ghostty が前面にあった」までしか見えず、後者は端末の中しか見ない。
  # 両方あって初めて時系列が繋がる。
  #
  # 本体は nix ではなく `uv tool install HPI` で入れる。HPI はモジュールを
  # 自分で書き換えて使う前提の設計 (editable install を推奨している) なので、
  # store に固めると噛み合わない。~/.local/bin は common.nix で PATH に入って
  # いるので、uv が置く `hpi` はそのまま通る。
  #
  # ライブラリとして使うときは `import my.core.init` を先に呼ぶこと。これが
  # sys.path への差し込みを実行する。`hpi` CLI 経由なら不要。
  home.file.".config/my/my/config.py".source = ../../configs/hpi/config.py;
  home.file.".config/my/my/activitywatch.py".source = ../../configs/hpi/activitywatch.py;
  home.file.".config/my/my/atuin.py".source = ../../configs/hpi/atuin.py;

  # LaTeX: latexmk default config (LuaLaTeX) and Japanese templates
  # latexmk 4.77+ officially supports $XDG_CONFIG_HOME/latexmk/latexmkrc, so use the XDG-compliant location
  home.file.".config/latexmk/latexmkrc".source = ../../configs/tex/latexmkrc;
  home.file.".config/tex/templates" = {
    source = ../../configs/tex/templates;
    recursive = true;
  };
  home.file.".config/mpv" = {
    source = ../../configs/media/mpv;
    recursive = true;
  };
  # uosc: stop vendoring (an 18MB bundled ziggy binary) and supply it from nixpkgs.
  # Keep third-party binaries out of the repo (the ziggy-dependent DL feature is unused).
  home.file.".config/mpv/scripts/uosc".source = "${pkgs.mpvScripts.uosc}/share/mpv/scripts/uosc";
  # …and its two fonts, which ship in the same package. They were 430KB of committed binary
  # that had to be kept in step with the script by hand.
  home.file.".config/mpv/fonts/uosc_icons.otf".source =
    "${pkgs.mpvScripts.uosc}/share/fonts/uosc_icons.otf";
  home.file.".config/mpv/fonts/uosc_textures.ttf".source =
    "${pkgs.mpvScripts.uosc}/share/fonts/uosc_textures.ttf";
  home.file.".config/launcher/config.toml".source = ../../configs/launcher/config.toml;
  # core/launcher.sh uses the store binary over a local build when this env is set.
  home.sessionVariables.LAUNCHER_SEARCH_BIN = lib.getExe launcher-search;
  home.file.".config/calcurse" = {
    source = ../../configs/cli/calcurse;
    recursive = true;
  };

}
