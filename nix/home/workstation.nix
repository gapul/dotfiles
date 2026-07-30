{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Search binary for the ghostty launcher. Store-ify it to protect it from gc-deep's target cleanup.
  launcher-search = pkgs.callPackage ../pkgs/launcher-search.nix { };
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
    radare2 # reverse engineering (r2)
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
    aerc # mail TUI
    isync # IMAP sync (mbsync)
    # Japanese proofreading textlint (whole ruleset pinned via buildNpmPackage; pnpm global retired)
    (callPackage ../pkgs/textlint-ja.nix { })
  ];

  # User data location (Google Drive mount / Syncthing share)
  home.activation.workstationDataDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p \
      "${config.home.homeDirectory}/Cloud" \
      "${config.home.homeDirectory}/Sync"
  '';

  # codex / claude: launch paths that don't read the env (CODEX_HOME / CLAUDE_CONFIG_DIR)
  # (GUI apps like CodexBar, popo's env-less spawn) regenerate ~/.codex ~/.claude and
  # cause a split, so symlink them to the XDG entities so every path converges on the
  # same location (same technique as .supermaven).
  home.file.".codex".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/codex";
  home.file.".claude".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/claude";

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
  home.file.".config/launcher/config.toml".source = ../../configs/launcher/config.toml;
  # core/launcher.sh uses the store binary over a local build when this env is set.
  home.sessionVariables.LAUNCHER_SEARCH_BIN = lib.getExe launcher-search;
  home.file.".config/calcurse" = {
    source = ../../configs/cli/calcurse;
    recursive = true;
  };

  # Zed: manage only settings.json (mkOutOfStoreSymlink so UI edits write straight into the repo).
  # Other ~/.config/zed/* are state like conversation history, so leave them alone.
  home.file.".config/zed/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/editors/zed/settings.json";
}
