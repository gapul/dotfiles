# CLI tools component (ECS: profile). bat/lazygit/eza/zoxide/fzf/atuin/direnv.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  c = import ../../lib/theme.nix; # c.dark / c.light (hex without leading #)

  # yazi's plugins and flavors used to be committed next to package.toml — which already said
  # exactly where each one came from and at which revision. So fetch them instead: nixpkgs
  # packages eight of the nine plugins (listed one by one below), and the rest are the
  # revisions package.toml pinned.

  rosePineTmThemes = import ../../lib/rose-pine-tm-theme.nix { inherit pkgs; };

  yamb = pkgs.fetchFromGitHub {
    owner = "h-hg";
    repo = "yamb.yazi";
    rev = "971b85862a1a2c5b8133da88b0dd4569adff296e";
    hash = "sha256-pbwKj4NuIiBMyuRVtbOYWBREZbyg1mKLoCWIAkxrygc=";
  };

  rosePine = pkgs.fetchFromGitHub {
    owner = "Mintass";
    repo = "rose-pine.yazi";
    rev = "d91f8f2";
    hash = "sha256-+7viMu6pCL49avTGUDufobpqg149PLkLiLvWAGJSgIM=";
  };

  # Upstream ships the dark flavor only; the dawn one is it with the palette swapped, which is
  # how it was made by hand before. The two extra tones are Rosé Pine's highlight med/high,
  # which palettes.json does not carry.
  dawnSwaps =
    (lib.filterAttrs (_: v: builtins.isString v && builtins.match "[0-9a-f]{6}" v != null) c.dark)
    // {
      highlightMed = "21202e";
      highlightHigh = "524f67";
    };
  dawnColors = c.light // {
    highlightMed = "f4ede8";
    highlightHigh = "cecacd";
  };

  rosePineDawn = pkgs.runCommand "rose-pine-dawn.yazi" { } ''
    cp -r ${rosePine} $out
    chmod -R u+w $out
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: hex: "sed -i 's/#${hex}/#${dawnColors.${name}}/g' $out/flavor.toml $out/tmtheme.xml"
      ) dawnSwaps
    )}
  '';
in
{
  programs.bat = {
    enable = true;
    config = {
      style = "numbers,changes,header";
      # Auto-follows the macOS appearance. dark=rose-pine / light=rose-pine-dawn.
      theme = "auto:system";
      theme-dark = "rose-pine";
      theme-light = "rose-pine-dawn";
    };
    # Rosé Pine's own tmThemes, registered in the bat cache (see lib/rose-pine-tm-theme.nix).
    themes."rose-pine" = {
      src = rosePineTmThemes;
      file = "dist/rose-pine.tmTheme";
    };
    themes."rose-pine-dawn" = {
      src = rosePineTmThemes;
      file = "dist/rose-pine-dawn.tmTheme";
    };
  };

  # lazygit: use ANSI color names to ride the terminal palette, tied to ghostty following the macOS appearance.
  # (dropping fixed hex rounds color precision to the terminal's 16 colors, but gives automatic dark/light switching)
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        nerdFontsVersion = "3";
        skipRewordInEditorWarning = true;
        theme = {
          activeBorderColor = [
            "magenta" # ~iris
            "bold"
          ];
          inactiveBorderColor = [ "blue" ]; # ~pine
          optionsTextColor = [ "cyan" ]; # ~foam
          selectedLineBgColor = [ "blue" ];
          cherryPickedCommitBgColor = [ "magenta" ];
          cherryPickedCommitFgColor = [ "blue" ];
          unstagedChangesColor = [ "red" ]; # ~love
          defaultFgColor = [ "default" ];
        };
      };
      git.pagers = [
        {
          colorArg = "always";
          pager = "${lib.getExe pkgs.delta} --color-only --paging=never";
        }
      ];
      customCommands = [
        {
          key = "d";
          context = "worktrees";
          description = "Move worktree to Trash";
          loadingText = "Moving worktree to Trash";
          output = "log";
          prompts = [
            {
              type = "confirm";
              title = "Trash worktree";
              body = ''
                Move worktree to Trash?

                Path:   {{.SelectedWorktree.Path}}
                Branch: {{.SelectedWorktree.Branch}}
              '';
            }
          ];
          command = ''
            {{- if .SelectedWorktree.IsMain -}}
            echo "Cannot trash the main worktree" >&2; exit 1
            {{- else if .SelectedWorktree.IsCurrent -}}
            echo "Cannot trash the current worktree" >&2; exit 1
            {{- else -}}
            ${lib.getExe pkgs.trash-cli} -- {{.SelectedWorktree.Path | quote}} && git worktree prune
            {{- end -}}
          '';
        }
      ];
    };
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    git = true;
    icons = "auto";
    extraOptions = [ "--group-directories-first" ];
  };

  programs.zoxide = {
    enable = true;
    # Same as atuin/direnv: the generated eval spawns a process per shell. Re-emitted
    # through evalcache in the initContent block below.
    enableZshIntegration = false;
  };

  programs.fzf = {
    enable = true;
    # Same reason. Home-manager deliberately emits fzf before atuin so that atuin's Ctrl+R
    # wins over fzf's unconditional binding; the block below keeps fzf ahead of atuin too.
    enableZshIntegration = false;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    # Inherit the terminal's 16-color ANSI -> automatically rides ghostty's Rose Pine / Rose Pine Dawn
    # (following the macOS appearance). Dropping fixed hex enables automatic dark/light switching.
    defaultOptions = [ "--color=16" ];
  };

  programs.atuin = {
    enable = true;
    # The generated hook is a plain `eval "$(atuin init zsh)"`, which costs ~37ms per shell.
    # Emit it ourselves through evalcache instead (see initContent below).
    enableZshIntegration = false;
    # Yield Up to history-substring-search. atuin launches only via Ctrl+R
    flags = [ "--disable-up-arrow" ];
    settings = {
      # Sync history across multiple machines (Mac / WSL / Linux server) via the official SaaS.
      # Requires `atuin login -u gapul` (or register) once per machine before use.
      # The E2E encryption key is ~/.local/share/atuin/key; backing it up to Bitwarden is recommended.
      auto_sync = true;
      sync_address = "https://api.atuin.sh";
      sync_frequency = "5m";
      update_check = false;
      search_mode = "fuzzy";
      filter_mode = "global"; # search across all hosts
      style = "compact";
      inline_height = 20;
      enter_accept = false; # Enter edits instead of executing
      show_preview = true;
      # Suppress the TUI debug log (~/.atuin/logs) to avoid cluttering the home dir.
      # config/data are already XDG (~/.config/atuin, ~/.local/share/atuin).
      logs.enabled = false;
      # Set no explicit theme and use the terminal's default colors -> tied to ghostty following the macOS appearance.
    };
  };

  programs.direnv = {
    enable = true;
    # Same reason as atuin: the generated `eval "$(direnv hook zsh)"` costs ~37ms per shell.
    enableZshIntegration = false;
    nix-direnv.enable = true;
  };

  # Cached replacements for the integrations disabled above. evalcache is defined in
  # configs/shell/zshrc.common, which shell.nix sources earlier in initContent.
  # The store paths are keyed into the cache file name, so a rebuild invalidates them.
  # mkOrder 1200 keeps them where home-manager used to emit them: after the main initContent
  # but before zsh-syntax-highlighting, which wants to be sourced once every widget exists.
  programs.zsh.initContent = lib.mkMerge [
    # zoxide and fzf keep the exact orders home-manager emitted them at. Moving them later
    # is not cosmetic: fzf binds TAB, so after fzf-tab's plugin load it would win and TAB
    # would fall back from fzf-tab-complete to fzf-completion.
    (lib.mkOrder 851 ''
      evalcache ${lib.getExe config.programs.zoxide.package} init zsh
    '')
    (lib.mkOrder 910 ''
      if [[ $options[zle] = on ]]; then
        evalcache ${lib.getExe config.programs.fzf.package} --zsh
      fi
    '')
    (lib.mkOrder 1200 ''
      evalcache ${lib.getExe config.programs.direnv.package} hook zsh
      if [[ $options[zle] = on ]]; then
        # atuin init forks `atuin uuid` unless the session id is already set, and it is the
        # single most load-sensitive line left (7ms idle, 128ms on a busy machine). The id is
        # just an opaque 32-digit hex, so zsh can make one without starting a process.
        if [[ -z ''${ATUIN_SESSION-} || ''${ATUIN_SHLVL-} != $SHLVL ]]; then
          printf -v ATUIN_SESSION '%04x%04x%04x%04x%04x%04x%04x%04x' \
            $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM
          export ATUIN_SESSION ATUIN_SHLVL=$SHLVL
        fi
        evalcache ${lib.getExe config.programs.atuin.package} init zsh --disable-up-arrow
      fi
    '')
  ];

  # Symlink dotfiles/configs/* (OS-independent ones only. Mac-only = sketchybar/karabiner go to home/darwin.nix)
  home.file.".config/gh/config.yml".source = ../../../configs/cli/gh/config.yml;
  # gh-dash / slk: hand-written configs that lived only on the machine until 2026-08.
  # gh-dash rewrites its config only when you edit it from the TUI, and slk's is a static
  # workspace list, so a read-only store symlink is fine for both.
  home.file.".config/gh-dash/config.yml".source = ../../../configs/cli/gh-dash/config.yml;
  home.file.".config/slk/config.toml".source = ../../../configs/cli/slk/config.toml;
  # markdownlint-cli2: parent-directory lookup makes this the default for all Markdown under home,
  # so despite not being XDG-compliant, the home dir root is the correct location per the tool's spec.
  home.file.".markdownlint-cli2.jsonc".source =
    ../../../configs/cli/markdownlint/markdownlint-cli2.jsonc;
  # ~/.local/bin, not ~/bin: the XDG user-binary location, already on PATH and already home to the
  # rest of the hand-written commands. ~/bin is retired.
  home.file.".local/bin/nssh" = {
    source = ../../../configs/bin/nssh;
    executable = true;
  };
  home.file.".local/bin/fzf-preview-repo" = {
    source = ../../../configs/bin/fzf-preview-repo;
    executable = true;
  };
  # yazi's Linux openers call this; on a desktop Linux box it just delegates to xdg-open.
  # Remote hosts get it from nssh instead (they never run home-manager).
  home.file.".local/bin/open-on-mac" = {
    source = ../../../configs/bin/open-on-mac;
    executable = true;
  };
  home.file.".config/yazi" = {
    source = ../../../configs/cli/yazi;
    recursive = true;
  };
  home.file.".config/yazi/plugins/full-border.yazi".source = pkgs.yaziPlugins.full-border;
  home.file.".config/yazi/plugins/git.yazi".source = pkgs.yaziPlugins.git;
  home.file.".config/yazi/plugins/jump-to-char.yazi".source = pkgs.yaziPlugins.jump-to-char;
  home.file.".config/yazi/plugins/piper.yazi".source = pkgs.yaziPlugins.piper;
  home.file.".config/yazi/plugins/smart-enter.yazi".source = pkgs.yaziPlugins.smart-enter;
  home.file.".config/yazi/plugins/smart-filter.yazi".source = pkgs.yaziPlugins.smart-filter;
  home.file.".config/yazi/plugins/smart-paste.yazi".source = pkgs.yaziPlugins.smart-paste;
  home.file.".config/yazi/plugins/toggle-pane.yazi".source = pkgs.yaziPlugins.toggle-pane;
  home.file.".config/yazi/plugins/yamb.yazi".source = yamb;
  home.file.".config/yazi/flavors/rose-pine.yazi".source = rosePine;
  home.file.".config/yazi/flavors/rose-pine-dawn.yazi".source = rosePineDawn;
}
