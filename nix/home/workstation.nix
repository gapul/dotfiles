{
  config,
  pkgs,
  lib,
  nixpkgsAgents,
  ...
}:
let
  fastPkgs = import ../lib/unstable-pkgs.nix {
    nixpkgsUnstable = nixpkgsAgents;
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  agentStateRepo = "${config.home.homeDirectory}/Developer/github.com/gapul/ai-agent-state";
  claudeConfig = path: config.lib.file.mkOutOfStoreSymlink "${agentStateRepo}/claude/${path}";
in
{
  # workstation layer: dev/daily tools for the main machine (laptop) / WSL / linux.
  # macmini (headless AI node) doesn't load this (split from common.nix 2026-07-19).

  home.packages =
    with pkgs;
    [
      # mpv itself. It stayed on brew for a long time because of a note saying "nixpkgs mpv doesn't
      # support aarch64-darwin", but when checked on 2026-08-30, 0.41.0 was cached and worked fine
      # (the note was outdated). uosc was already from nixpkgs, so now the player and scripts share a source.
      mpv
      pandoc # document conversion
      # Ears for the music tooling: aubiopitch / aubiotempo / aubioonset turn a rendered wav into
      # numbers an agent can check (is the melody the one I wrote, is the tempo 100). The other
      # half, `sox ... spectrogram`, is sox which is already here. See ~/tmp/music-tools-test/listen.
      # 26.05 marks aubio linux-only; nixos-unstable builds it on aarch64-darwin (0.4.9, cached).
      fastPkgs.aubio
      # LilyPond: text -> engraved score (PDF/PNG/MIDI). MuseScore's CLI covers MIDI -> score,
      # this is for notation written as text in the first place.
      lilypond
      # MeshLab's scripting side. meshlabserver was dropped in 2020.x; the filters are driven
      # from Python via pymeshlab instead. Wrapped as its own interpreter so it does not shadow
      # the main python3 on PATH: `pymeshlab-python script.py`.
      (writeShellScriptBin "pymeshlab-python" ''
        exec ${python3.withPackages (ps: [ ps.pymeshlab ])}/bin/python3 "$@"
      '')
      typst # typesetting
      # Circuit simulation. kicad-cli (KiCad 10, /Applications/KiCad) exports a SPICE netlist
      # from a schematic; ngspice -b runs it; gnuplot turns wrdata output into a PNG the agent
      # can read. Verified with an RC low-pass: -3 dB at 1585 Hz against 1592 theoretical.
      ngspice
      gnuplot
      # build123d: Python CAD (OpenCascade via cadquery-ocp) for the parts OpenSCAD's CSG cannot
      # do well - fillets, threads, constraints. Neither is in nixpkgs, so this is the sanctioned
      # uv exception (see keychip-case for the per-repo form): uv resolves build123d on demand
      # into its cache and pins Python 3.12, the newest with cadquery-ocp wheels.
      # `build123d-python script.py` / `build123d-python -c '...'`.
      (writeShellScriptBin "build123d-python" ''
        exec ${lib.getExe uv} run --quiet --python 3.12 --with build123d python "$@"
      '')
      # Compose the TeX Live collections needed for Japanese academic documents via Nix.
      # Avoid scheme-full while covering math, figures/tables, bibliographies, and common
      # extra packages without adding them individually.
      (texliveMedium.withPackages (
        ps: with ps; [
          latexmk
          collection-langjapanese
          collection-latexextra
          collection-mathscience
          collection-bibtexextra
          collection-fontsrecommended
        ]
      ))
      poppler-utils # PDF CLI (pdftotext etc. formerly brew poppler)
      fastPkgs.bitwarden-cli # Bitwarden (bw)
      fastPkgs.syft # SBOM
      radare2 # reverse engineering (r2), small native binaries (e.g. REAPER)
      # app / binary analysis: unofficial-client recon + Mac proprietary-app RE
      jadx # APK: dex -> readable Java
      apkeep # APK/XAPK downloader (Play / APKPure)
      asar # extract Electron app.asar (e.g. Native Access)
      cfr # JVM decompiler (e.g. Bitwig jars)
      aria2 # downloader (aria2c)
      legendary-gl # Epic Games CLI (legendary): install/update Unreal Engine + games without the official launcher
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
      # Container runtimes belong on the server hosts.  This workstation keeps
      # only client/dev tooling and delegates container workloads to them.
      fontforge # font editing CLI (no GUI: the only macOS GUI build is x86_64)
      python3Packages.fonttools # font manipulation lib/CLI
      stockfish # chess engine, spoken to over UCI (the Puddle chess wallpaper's opponent)
      aerc # mail TUI
      isync # IMAP sync (mbsync)
      # Japanese proofreading textlint (whole ruleset pinned via buildNpmPackage; pnpm global retired)
      (callPackage ../pkgs/textlint-ja.nix { })
    ]
    # apktool pulls in aapt, which nixpkgs marks unavailable on aarch64-linux (CI cross-evaluates).
    # This is the mac workstation, so keep it darwin-only.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.apktool ];

  # User data location: everything that also lives somewhere else sits under ~/Sync (2026-08).
  # google-drive-* are rclone mounts (remote-primary, see home/rclone-mount.nix), syncthing holds
  # real local files (local-primary, the only one restic backs up).
  home.activation.workstationDataDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p \
      "${config.home.homeDirectory}/Sync/google-drive" \
      "${config.home.homeDirectory}/Sync/google-drive-school" \
      "${config.home.homeDirectory}/Sync/google-drive-work" \
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
  # Vendored skills (cloudflare/*, wrangler, ...) stay unmanaged: they are
  # re-installable from upstream. Workstation-only because the hooks are desktop-specific
  # (osascript notifications, herdr) — move this to modules/home/agents.nix to share it.
  xdg.configFile = {
    "claude/settings.json".source = claudeConfig "settings.json";
    "claude/hooks".source = claudeConfig "hooks";
    "claude/bin".source = claudeConfig "bin";
    "claude/skills/anki-add".source = claudeConfig "skills/anki-add";
    "claude/skills/gapul-writing-voice".source = claudeConfig "skills/gapul-writing-voice";
    "claude/skills/step-by-step-tutor".source = claudeConfig "skills/step-by-step-tutor";
  };

  # Codex: the herdr SessionStart hook reports the codex session id over the herdr socket,
  # which is the only way herdr can resume the pane's agent after a reboot (claude does the
  # same through configs/cli/claude/hooks). Without it a codex pane comes back as a bare shell.
  # The script is an out-of-store symlink so `herdr integration install codex` can update it
  # straight into the repo; hooks.json is generated here because the upstream file hardcodes
  # an absolute macOS path that would be wrong on the Linux workstations.
  xdg.dataFile."codex/herdr-agent-state.sh".source =
    config.lib.file.mkOutOfStoreSymlink "${agentStateRepo}/codex/herdr-agent-state.sh";
  xdg.dataFile."codex/hooks.json".text = builtins.toJSON {
    hooks.SessionStart = [
      {
        hooks = [
          {
            type = "command";
            command = "bash '${config.xdg.dataHome}/codex/herdr-agent-state.sh' session";
            timeout = 10;
          }
        ];
      }
    ];
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
  # HPI (Human Programming Interface). A framework for keeping exports pulled from SaaS in a
  # form that can be queried across sources locally.
  #
  # `~/.config/my` is loaded as the my.config package. HPI's my/core/init.py inserts
  # MY_CONFIG (default: platformdirs' user_config_dir) at the front of sys.path, so files
  # placed here can be imported as `my.*` as an implicit namespace package. No __init__.py
  # is needed (PEP 420).
  #
  # activitywatch.py and atuin.py don't exist upstream, so they're custom. ActivityWatch is the
  # largest body of local data in this environment (1.15 million events measured), yet HPI only
  # had arbtt and rescuetime. atuin is missing too. The former only sees "Ghostty was in front"
  # and the latter only sees inside the terminal. Only with both does the timeline connect.
  #
  # HPI itself is installed with `uv tool install HPI`, not nix. HPI is designed to be used
  # by editing its modules yourself (it recommends an editable install), so freezing it in
  # the store doesn't fit. ~/.local/bin is on PATH via common.nix, so the `hpi` that uv
  # installs works as is.
  #
  # When using it as a library, call `import my.core.init` first. That performs the sys.path
  # insertion. Not needed via the `hpi` CLI.
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
  home.file.".config/calcurse" = {
    source = ../../configs/cli/calcurse;
    recursive = true;
  };

}
