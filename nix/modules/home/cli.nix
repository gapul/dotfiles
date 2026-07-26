# CLI tools component (ECS: profile)。bat/lazygit/eza/starship/zoxide/fzf/atuin/direnv。
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
      # macOS 外観に自動追従。dark=rose-pine / light=rose-pine-dawn。
      theme = "auto:system";
      theme-dark = "rose-pine";
      theme-light = "rose-pine-dawn";
    };
    # Rosé Pine tmTheme を vendor (bat cache に登録される)。dawn は dark を hex 置換で生成。
    themes."rose-pine" = {
      src = ../../../configs/cli/bat/themes;
      file = "rose-pine.tmTheme";
    };
    themes."rose-pine-dawn" = {
      src = ../../../configs/cli/bat/themes;
      file = "rose-pine-dawn.tmTheme";
    };
  };

  # lazygit: ANSI 名前色で端末パレットに乗せ、ghostty の macOS 外観追従に連動させる。
  # (固定 hex をやめたぶん色精度は端末の 16 色に丸まるが dark/light 自動切替になる)
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        nerdFontsVersion = "3";
        skipRewordInEditorWarning = true;
        theme = {
          activeBorderColor = [
            "magenta" # iris 相当
            "bold"
          ];
          inactiveBorderColor = [ "blue" ]; # pine 相当
          optionsTextColor = [ "cyan" ]; # foam 相当
          selectedLineBgColor = [ "blue" ];
          cherryPickedCommitBgColor = [ "magenta" ];
          cherryPickedCommitFgColor = [ "blue" ];
          unstagedChangesColor = [ "red" ]; # love 相当
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
    # 端末の 16 色 ANSI を継承 → ghostty の Rose Pine / Rose Pine Dawn (macOS 外観追従)
    # に自動で乗る。固定 hex をやめることで dark/light 自動切替に対応。
    defaultOptions = [ "--color=16" ];
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    # Up は history-substring-search に明け渡す。atuin は Ctrl+R のみで起動
    flags = [ "--disable-up-arrow" ];
    settings = {
      # 公式 SaaS で複数端末 (Mac / WSL / Linux server) の history を同期。
      # 利用前に各端末で 1 度だけ `atuin login -u gapul` (or register) が必要。
      # E2E 暗号化キーは ~/.local/share/atuin/key、Bitwarden に backup 推奨。
      auto_sync = true;
      sync_address = "https://api.atuin.sh";
      sync_frequency = "5m";
      update_check = false;
      search_mode = "fuzzy";
      filter_mode = "global"; # 全 host 横断検索
      style = "compact";
      inline_height = 20;
      enter_accept = false; # Enter で実行せず編集に
      show_preview = true;
      # TUI デバッグログ(~/.atuin/logs)を抑止し home 直下を汚さない。
      # config/data は既に XDG (~/.config/atuin, ~/.local/share/atuin)。
      logs.enabled = false;
      # 明示テーマは付けず端末のデフォルト配色を使う → ghostty の macOS 外観追従に連動。
    };
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
  # dotfiles/configs/* を symlink (OS 非依存なものだけ。Mac 専用 = aerospace/sketchybar/karabiner は home/darwin.nix へ)
  home.file.".config/starship.toml".source = ../../../configs/shell/starship.toml;
  home.file.".config/gh/config.yml".source = ../../../configs/cli/gh/config.yml;
  # markdownlint-cli2: 親方向探索でホーム以下全 Markdown の既定になるため、
  # XDG 非対応だがホーム直下がツールの仕様上正しい置き場所。
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
