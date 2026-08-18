{
  config,
  lib,
  pkgs,
  user,
  nixIndexDatabase,
  agentSkills,
  ...
}:
let
  # SSO for XDG-relocation exports (shared with shell.nix envExtra).
  xdgEnv = import ../lib/shell-xdg-env.nix;
in
{
  imports = [
    nixIndexDatabase.homeModules.default
    agentSkills.homeManagerModules.default
    ../modules/home/git.nix
    ../modules/home/cli.nix
    ../modules/home/nix-tools.nix
    ../modules/home/shell.nix
    ../modules/home/packages.nix
    ../modules/home/terminal.nix
    ../modules/home/editor.nix
    ../modules/home/agents.nix
  ];

  # OS-independent home-manager settings
  # OS-specific parts are split into home/darwin.nix / home/linux.nix / home/wsl.nix etc.

  home.username = user.username;
  home.stateVersion = "23.11";

  programs.home-manager.enable = true;

  # Don't generate HM option docs (man home-configuration.nix / options.json).
  # Removes the per-switch 'options.json ... without proper context' warning + slight speedup.
  # Refer to the home-manager official docs (online) for options.
  manual.manpages.enable = false;
  manual.json.enable = false;

  # Static env vars are read from configs/shell/env-vars.json (SSO, shared with
  # Win profile.ps1). Dynamic paths (HOME / XDG dependent) are added individually below.
  # The $comment field can't be passed to home.sessionVariables, so exclude it.
  home.sessionVariables =
    (lib.filterAttrs (n: _: n != "$comment") (
      builtins.fromJSON (builtins.readFile ../../configs/shell/env-vars.json)
    ))
    // {
      # ── Dynamic paths (HOME / XDG dependent, can't be in JSON) ──
      SOPS_AGE_KEY_FILE = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

      # XDG Base Directory: explicit export for CLIs that reference $XDG_* at runtime
      # (home-manager only expands config.xdg.* at build time and doesn't put it in env)
      XDG_CONFIG_HOME = config.xdg.configHome;
      XDG_DATA_HOME = config.xdg.dataHome;
      XDG_STATE_HOME = config.xdg.stateHome;
      XDG_CACHE_HOME = config.xdg.cacheHome;

      # GnuPG: move the default ~/.gnupg to $XDG_DATA_HOME/gnupg. Upstream isn't XDG-aware,
      # so set it explicitly via GNUPGHOME. Dir perms must be 700 (chmod'd during migration).
      GNUPGHOME = "${config.xdg.dataHome}/gnupg";

      # Relocate cargo / bundler under XDG
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      BUNDLE_USER_CONFIG = "${config.xdg.configHome}/bundle/config";
      BUNDLE_USER_CACHE = "${config.xdg.cacheHome}/bundle";
      BUNDLE_USER_PLUGIN = "${config.xdg.dataHome}/bundle/plugin";

      # npm: relocate the upstream defaults (~/.npmrc / ~/.npm / ~/.npm-global) under XDG.
      NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/npmrc";
      NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
      NPM_CONFIG_PREFIX = "${config.xdg.dataHome}/npm";

      # PlatformIO: move the default ~/.platformio (GBs from toolchains etc.) to XDG data.
      PLATFORMIO_CORE_DIR = "${config.xdg.dataHome}/platformio";

      # Gradle: ~/.gradle had grown to 1.5GB here, and nothing on PATH put it there — it is the
      # Gradle bundled inside Android Studio. Data rather than cache: alongside the wrapper
      # distributions and build caches it is also where init scripts and gradle.properties
      # (signing keys, tokens) live, and those are not regenerable.
      GRADLE_USER_HOME = "${config.xdg.dataHome}/gradle";

      # Dart/Flutter: move the pub package cache ~/.pub-cache to XDG cache (re-fetchable).
      PUB_CACHE = "${config.xdg.cacheHome}/pub";
      # matplotlib: not XDG-aware on macOS, so set it explicitly via MPLCONFIGDIR.
      MPLCONFIGDIR = "${config.xdg.configHome}/matplotlib";

      # TeX Live: move the default ~/.texlive<year> (texmf-var/config cache) to XDG.
      # var/config are regenerated caches, so relocation is safe. The user texmf tree is
      # also consolidated under data via TEXMFHOME.
      TEXMFHOME = "${config.xdg.dataHome}/texmf";
      TEXMFVAR = "${config.xdg.cacheHome}/texlive/texmf-var";
      TEXMFCONFIG = "${config.xdg.configHome}/texlive/texmf-config";
    };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin" # hand-written commands (home.file.".local/bin/*") + uv tool binaries
    "${config.xdg.dataHome}/cargo/bin" # binaries from cargo install (CARGO_HOME/bin)
    "${config.xdg.dataHome}/npm/bin" # binaries from npm install -g (NPM_CONFIG_PREFIX/bin)
  ];

  # pnpm global config (pnpm 11+ uses YAML). Separate from NPM_CONFIG_USERCONFIG.
  # Supply-chain hardening: don't fetch versions published less than 14 days (20160 min) ago.
  # Emergencies only: pnpm install --config.minimumReleaseAge=0
  xdg.configFile."pnpm/config.yaml".text = ''
    minimumReleaseAge: 20160
  '';

  # Hand-rolled guarded .zshenv so the shell can start even if /nix is broken
  home.file.".zshenv" = {
    force = true;
    text = ''
      export ZDOTDIR="$HOME/.config/zsh"
      # CLAUDE_CONFIG_DIR is also in home.sessionVariables, but hm-session-vars.sh's
      # __HM_SESS_VARS_SOURCED guard can skip re-sourcing and leave it empty (old shells / GUI launch).
      # To avoid that, also export it explicitly in the guard-less .zshenv.
      export CLAUDE_CONFIG_DIR="$HOME/.config/claude"
      # Codex doesn't reference the split XDG dirs directly, so use the official CODEX_HOME
      # to relocate ~/.codex under XDG data/state.
      ${xdgEnv.codex}
      # For HISTFILE too, pin the XDG path early in the guard-less .zshenv so old/GUI-launched
      # shells that don't read .zshrc don't leak into ~/.zsh_history.
      export HISTFILE="$HOME/.local/state/zsh/history"
      # Same for GNUPGHOME. Running gpg from a zsh where it's unset regenerates an empty
      # ~/.gnupg, so pin it early in the guard-less .zshenv.
      export GNUPGHOME="$HOME/.local/share/gnupg"
      # npm too: pin its non-XDG defaults (~/.npmrc / ~/.npm) via env vars.
      ${xdgEnv.npm}
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        # nix-daemon.sh prints a "safely delete either" warning to stderr when both
        # ~/.nix-profile and the new profile exist. Both symlinks are kept intentionally,
        # so just swallow the warning (exports survive since it's sourced).
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null
      fi
      [ -f "$HOME/.local/state/nix/profile/etc/profile.d/hm-session-vars.sh" ] && \
        . "$HOME/.local/state/nix/profile/etc/profile.d/hm-session-vars.sh"
    '';
  };

  # Suppress login(1)'s "Last login: ..." line (standard macOS behavior, non-destructive).
  home.file.".hushlogin".text = "";

  # Location for sync/cloud data the user handles directly.
  # XDG is for app config/cache/state, so user data like Google Drive mounts or Syncthing
  # shared folders is grouped into categories directly under HOME.
  # On the workstation that category is ~/Sync (see home/workstation.nix), which holds both the
  # rclone mounts and the Syncthing share — anything whose data also exists somewhere else.
  home.activation.userDataDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p \
      "${config.xdg.dataHome}/codex" \
      "${config.xdg.stateHome}/codex/sqlite" \
      "${config.xdg.configHome}/npm" \
      "${config.xdg.cacheHome}/npm" \
      "${config.xdg.dataHome}/npm"
  '';

  # One-off CLI tools (not covered by programs.*, OS-independent)

  # SOPS definitions are split into home/secrets.nix (so macmini, which has no age key,
  # can share common.nix. 2026-07-19)

  # The same list modules/authorized-keys.nix declares system-side, written here too.
  #
  # Not redundant: sshd reads both ~/.ssh/authorized_keys and the nix-managed path
  # (authorizedKeysFiles defaults to ["%h/.ssh/authorized_keys" "/etc/ssh/authorized_keys.d/%u"],
  # and nix-darwin adds an AuthorizedKeysCommand on top). Declaring only the system side would
  # leave whatever was hand-placed in ~/.ssh still valid — macmini still carries a `root@pve` key
  # for a host dismantled in 2026-08. Owning the file is what actually removes those.
  #
  # Both copies come from one source, so they cannot disagree. The alternative — dropping
  # %h/.ssh/authorized_keys from authorizedKeysFiles — is a smaller diff but locks you out of a
  # remote host if the declared path is ever wrong, so it is not worth it for one saved file.
  home.file.".ssh/authorized_keys".source = ../keys/authorized_keys;

}
