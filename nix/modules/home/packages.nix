# Packages component (ECS: profile). One-off CLI tools (not covered by programs.*, OS-independent).
{
  pkgs,
  nixpkgsUnstable,
  ...
}:
let
  # nixos-unstable for what the 26.05 release branches don't carry yet (SSO: commonSpecialArgs).
  # Same escape hatch as home/darwin.nix, minus the allowUnfree re-import (these are all free).
  unstablePkgs = nixpkgsUnstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
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
    nixd # Nix LSP (used from Neovim)
    gh-nix # bridge gh auth temporarily into Nix access-tokens
    nix-output-monitor # make nh / nix build output readable (`nom`)
    nix-tree # nix store dependency TUI
    nix-init # generate flake.nix scaffolding
    nvd # package diff between Nix / Home Manager generations
    optnix # NixOS / Home Manager / nix-darwin option search TUI
    devenv # Nix-based dev shell (combined with direnv)
    nix-fast-build # parallel + remote nix build (speeds up self-built pkgs / flake checks)
    nixpkgs-review # build & review a nixpkgs PR / bump before applying it
    tealdeer # tldr CLI (manual because programs.tealdeer doesn't support archive_source)

    # ─── CLI migrated from Homebrew (stage 1: git-related + basics) ───
    gh # GitHub CLI
    gh-dash # GitHub PR / Issue dashboard TUI
    git-wt # unify worktree create/switch/safe-delete under `git wt`
    git-wtpr # `git wtpr <PR number|URL>` moves to a PR-dedicated worktree
    trash-cli # route git-wt deletions through the trash
    tirith # command/URL/Skill defense for shell/AI agents
    (callPackage ../../pkgs/tuicr.nix { }) # review AI-generated diffs in a PR-style UI
    ghq # repo clone management
    lazyjj # jujutsu TUI
    jq # JSON processor
    fd # find alternative (also used in fzf defaultCommand)
    just # command runner (runs this Justfile)
    bottom # system monitor (btm)
    dust # disk usage (formerly du-dust)
    ncdu # disk usage TUI
    yazi # file manager TUI
    tmux # terminal multiplexer (config in modules/home/terminal.nix)
    tmuxp # declare tmux sessions/layouts in YAML (~/.config/tmuxp/)
    # AI agent multiplexer (config in modules/home/terminal.nix). Goes on every host so
    # `herdr --remote` finds a version-matched binary on the far side instead of installing one
    # into ~/.local/bin. Not in the 26.05 branches yet, so it comes from unstable.
    unstablePkgs.herdr
    podman-tui # Podman container / image / Pod management TUI
    iamb # Matrix TUI (Vim keybindings, E2EE support)
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
    opencode # AI coding CLI
    (callPackage ../../pkgs/unity-cli.nix { }) # Unity Editor / module / project management CLI
    glow # markdown viewer
    visidata # CSV/TSV table viewer + editor (TUI, `vd`)
    chafa # image → terminal
    ddgr # DuckDuckGo interactive terminal search
    w3m # text browser

    # ─── nix-declaring things previously installed locally via cargo/uv (for reproducibility) ───

    # ─── CLI migrated from Homebrew (stage 3) ───
    ollama # local LLM (nix build has Metal GPU too — runner links Metal.framework. verified)
    neovim # the editor itself (config via mkOutOfStoreSymlink of configs/editors/nvim)

    # ─── for yazi preview (used via piper or the built-in previewer) ───
    ffmpegthumbnailer # video thumbnails (used by yazi's built-in video previewer)
    ouch # list/extract archive contents (zip/tar/7z etc.)
    rich-cli # rich formatting for csv/json/md etc. (called from piper previewer)

    # ─── centralized lint/format management (same binary/version across CLI, Neovim, CI) ───
    # Neovim (conform/nvim-lint) references these on PATH. On the Mason side,
    # excluded from ensure_installed to avoid double management (configs/editors/nvim/lua/plugins/tooling.lua).
    stylua # Lua formatting
    shfmt # Shell formatting
    prettier # js/ts/json/yaml/css/md formatting
    ruff # Python lint + format
    markdownlint-cli2 # Markdown lint
  ];
}
