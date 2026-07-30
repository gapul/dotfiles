# CLI tools component (ECS: profile). bat/lazygit/eza/starship/zoxide/fzf/atuin/direnv.
{
  pkgs,
  lib,
  ...
}:
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
    # Vendor the Rosé Pine tmTheme (registered in the bat cache). dawn is generated from dark by hex substitution.
    themes."rose-pine" = {
      src = ../../../configs/cli/bat/themes;
      file = "rose-pine.tmTheme";
    };
    themes."rose-pine-dawn" = {
      src = ../../../configs/cli/bat/themes;
      file = "rose-pine-dawn.tmTheme";
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

  # The true source of the starship config is configs/shell/starship.toml (symlinked via home.file below).
  # Adding programs.starship.settings here would make home-manager generate the same
  # ~/.config/starship.toml and collide with the symlink, so settings is left empty.
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    # Inherit the terminal's 16-color ANSI -> automatically rides ghostty's Rose Pine / Rose Pine Dawn
    # (following the macOS appearance). Dropping fixed hex enables automatic dark/light switching.
    defaultOptions = [ "--color=16" ];
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
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
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
  # Symlink dotfiles/configs/* (OS-independent ones only. Mac-only = aerospace/sketchybar/karabiner go to home/darwin.nix)
  home.file.".config/starship.toml".source = ../../../configs/shell/starship.toml;
  home.file.".config/gh/config.yml".source = ../../../configs/cli/gh/config.yml;
  # markdownlint-cli2: parent-directory lookup makes this the default for all Markdown under home,
  # so despite not being XDG-compliant, the home dir root is the correct location per the tool's spec.
  home.file.".markdownlint-cli2.jsonc".source =
    ../../../configs/cli/markdownlint/markdownlint-cli2.jsonc;
  home.file."bin/nssh" = {
    source = ../../../configs/bin/nssh;
    executable = true;
  };
  home.file."bin/fzf-preview-repo" = {
    source = ../../../configs/bin/fzf-preview-repo;
    executable = true;
  };
  home.file.".config/yazi" = {
    source = ../../../configs/cli/yazi;
    recursive = true;
  };
}
