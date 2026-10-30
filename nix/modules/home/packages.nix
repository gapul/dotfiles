# Packages component (ECS: profile). One-off CLI tools (not covered by programs.*, OS-independent).
{
  pkgs,
  llmAgents,
  nixpkgsUnstable,
  ...
}:
let
  # Fast-moving CLIs are a separate lineage. allowUnfree is also set explicitly here.
  agentPkgs = import ../../lib/unstable-pkgs.nix {
    inherit nixpkgsUnstable;
    inherit (pkgs.stdenv.hostPlatform) system;
  };
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
  # matrix-commander-rs creates every room encrypted, which this homeserver deliberately avoids
  # (nix/homelab/matrix-bridges-v2.nix: a single-admin server gains nothing from E2BE and loses
  # bot access and history). Its `--plain true` turns that off, but passing it unconditionally
  # would also send plaintext into existing encrypted rooms, which is the one thing this client
  # is here for. So inject it for room creation only. `--visibility private` already works; the
  # "visibility: Public" it prints afterwards is a display bug, not the stored value.
  matrix-commander-rs = pkgs.writeShellApplication {
    name = "matrix-commander-rs";
    text = ''
      plain=()
      for arg in "$@"; do
        case "$arg" in
          --room-create | --room-dm-create)
            plain=(--plain true)
            break
            ;;
        esac
      done
      exec ${pkgs.matrix-commander-rs}/bin/matrix-commander-rs "''${plain[@]}" "$@"
    '';
  };
  git-wtpr = pkgs.callPackage ../../pkgs/git-wtpr.nix { };
in
{
  home.packages = with pkgs; [
    nixd # Nix LSP (used from Neovim)
    nixfmt # Nix formatter: nixd formats with it in Neovim (same as nix fmt / treefmt)
    statix # Nix linter: suggests simpler idioms (nvim-lint)
    deadnix # Nix linter: unused bindings and arguments (nvim-lint)
    gh-nix # bridge gh auth temporarily into Nix access-tokens
    nix-output-monitor # make nh / nix build output readable (`nom`)
    nix-tree # nix store dependency TUI
    nix-init # generate flake.nix scaffolding
    nvd # package diff between Nix / Home Manager generations
    optnix # NixOS / Home Manager / nix-darwin option search TUI
    devenv # Nix-based dev shell (combined with direnv)
    nix-fast-build # parallel + remote nix build (speeds up self-built pkgs / flake checks)
    nixpkgs-review # build & review a nixpkgs PR / bump before applying it
    nurl # print a fetcher call (fetchFromGitHub etc.) with its hash filled in, for pkgs/
    nix-melt # flake.lock viewer TUI (which input pulled which nixpkgs, how stale each pin is)
    nixos-anywhere # install a NixOS host over SSH (kexec + disko + nixos-install in one command)
    tealdeer # tldr CLI (manual because programs.tealdeer doesn't support archive_source)

    # ─── CLI migrated from Homebrew (stage 1: git-related + basics) ───
    gh # GitHub CLI
    gh-dash # GitHub PR / Issue dashboard TUI
    git-wt # unify worktree create/switch/safe-delete under `git wt`
    git-wtpr # `git wtpr <PR number|URL>` moves to a PR-dedicated worktree
    trash-cli # route git-wt deletions through the trash
    (callPackage ../../pkgs/tuicr.nix { }) # review AI-generated diffs in a PR-style UI
    (callPackage ../../pkgs/agent-access.nix { }) # aac: inject one approved Bitwarden credential into an agent's command
    ghq # repo clone management
    git-annex # content-addressed large files in git (fonts / assets; see homelab/git-annex.nix)
    lazyjj # jujutsu TUI
    jq # JSON processor
    fd # find alternative (also used in fzf defaultCommand)
    ripgrep # grep alternative (LazyVim's project search and pickers need rg)
    just # command runner (runs this Justfile)
    bottom # system monitor (btm)
    dust # disk usage (formerly du-dust)
    ncdu # disk usage TUI
    xdg-ninja # lists dotfiles in ~ that could live under XDG dirs (`xdg-ninja --skip-ok --skip-unsupported`)
    yazi # file manager TUI
    tmux # terminal multiplexer (config in modules/home/terminal.nix)
    tmuxp # declare tmux sessions/layouts in YAML (~/.config/tmuxp/)
    # AI agent multiplexer (config in modules/home/terminal.nix). Goes on every host so
    # `herdr --remote` finds a version-matched binary on the far side instead of installing one
    # into ~/.local/bin. Not in the 26.05 series yet, so from the unstable lineage.
    agentPkgs.herdr
    podman-tui # Podman container / image / Pod management TUI
    iamb # Matrix TUI (Vim keybindings, E2EE support)
    # Matrix CLI for agents acting as the human account (E2EE via vodozemac, no olm), so it
    # reaches encrypted rooms the curl wrappers in home/matrix-cli.nix cannot. One-time
    # `--login password` and an Element device verification; credentials land in
    # ~/.local/share/matrix-commander-rs. `--output json` for machine consumption.
    matrix-commander-rs # wrapper defined above
    newsboat # RSS/Atom feed reader TUI
    presenterm # Markdown presentation TUI
    termshark # tshark/Wireshark packet analysis TUI

    # ─── CLI migrated from Homebrew (stage 2: build/language/docs/security/network) ───
    uv # Python package management
    pnpm # Node package management
    imagemagick # image conversion (magick)
    libsixel # sixel (img2sixel)
    age # SOPS encryption backend
    sops # secrets management
    gitleaks # secret leak scanning for pre-commit
    pre-commit # hook framework
    (callPackage ../../pkgs/unity-cli.nix { }) # Unity Editor / module / project management CLI
    glow # markdown viewer
    visidata # CSV/TSV table viewer + editor (TUI, `vd`)
    chafa # image → terminal
    ddgr # DuckDuckGo interactive terminal search
    w3m # text browser (the mature one; called as a pager or external renderer)
    # chawan: the newer terminal browser (`cha`). Unlike w3m it interprets CSS and can show images
    # via sixel and kitty graphics — Ghostty speaks the latter, so images actually render.
    # JS partly works too. It doesn't replace w3m; the split is w3m for plain reading and chawan
    # where appearance matters.
    #
    # Gotcha: all https fails with "unexpected eof while reading". chawan's http adapter calls OpenSSL
    # directly and only looks at SSL_CERT_FILE, while this environment only had NIX_SSL_CERT_FILE.
    # Solved by adding SSL_CERT_FILE in home/common.nix.
    chawan

    # ─── nix-declaring things previously installed locally via cargo/uv (for reproducibility) ───

    # ─── for yazi preview (used via piper or the built-in previewer) ───
    ffmpegthumbnailer # video thumbnails (used by yazi's built-in video previewer)
    ouch # list/extract archive contents (zip/tar/7z etc.)
    rich-cli # rich formatting for csv/json/md etc. (called from piper previewer)

    # ─── centralized lint/format management (same binary/version across CLI, Neovim, CI) ───
    # Neovim (conform/nvim-lint) references these on PATH. Mason is disabled
    # (configs/editors/nvim/lua/plugins/tooling.lua), so nothing else installs them.
    stylua # Lua formatting
    shfmt # Shell formatting
    prettier # js/ts/json/yaml/css/md formatting
    ruff # Python lint + format
    markdownlint-cli2 # Markdown lint
    markdown-toc # Markdown TOC (conform formatter from LazyVim's markdown extra)

    # ─── LSP servers for the LazyVim extras in lazyvim.json (used to come from Mason) ───
    # clangd is not here: /usr/bin/clangd from the Command Line Tools knows the macOS SDK.
    # ocamllsp and prolog_ls come from opam and the swipl pack (plugins/ocaml.lua, prolog.lua).
    lua-language-server # lua_ls
    marksman # Markdown
    pyright # Python (ruff above doubles as its LSP)
    texlab # LaTeX
    vtsls # TypeScript / JavaScript
    vscode-langservers-extracted # eslint (vscode-eslint-language-server)
  ];

  # AI coding CLI; even nixpkgs-unstable trails its release cadence (see the llm-agents input).
  # Updates come only from rebuilds, so its own self-updater stays off.
  programs.opencode = {
    enable = true;
    package = llmAgents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
    settings.autoupdate = false;
  };

  # iamb (Matrix TUI, in home.packages above): same homeserver as Element. Every host that has
  # the binary gets the profile, so the laptop does not need a hand-written login.
  # Session state and E2EE keys go to ~/.local/share/iamb on first login, not declared here.
  # Plain text rather than pkgs.formats.toml: see the lazygit note in home/darwin.nix (CI platform mismatch).
  xdg.configFile."iamb/config.toml".text = ''
    default_profile = "gapul"

    [profiles.gapul]
    user_id = "@gapul:gapul.net"
    url = "https://matrix.gapul.net"
  '';
}
