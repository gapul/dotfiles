# GitHub Copilot integration configuration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.copilot;
in

{
  options.dotfiles.development.copilot = {
    enable = mkEnableOption "GitHub Copilot integration";
    
    cli.enable = mkEnableOption "GitHub Copilot CLI integration" // { default = true; };
    
    editors = {
      neovim.enable = mkEnableOption "Neovim Copilot integration" // { default = true; };
      vscode.enable = mkEnableOption "VSCode Copilot integration" // { default = true; };
    };
    
    features = {
      autoCompletion = mkEnableOption "Auto-completion suggestions" // { default = true; };
      codeReview = mkEnableOption "Code review assistance" // { default = true; };
      chatIntegration = mkEnableOption "Copilot Chat integration" // { default = true; };
      commandSuggestions = mkEnableOption "Command-line suggestions" // { default = true; };
    };
  };

  config = mkIf cfg.enable {
    # GitHub CLI with Copilot extension
    home-manager.users.yuki.home.packages = with pkgs; [
      gh  # GitHub CLI (includes Copilot functionality)
    ];

    # Neovim Copilot configuration
    home-manager.users.yuki.programs.neovim = mkIf cfg.editors.neovim.enable {
      plugins = with pkgs.vimPlugins; [
        # Core Copilot plugin
        copilot-vim
        
        # Optional: Copilot Chat (if available)
        # copilot-chat-nvim
        
        # LSP support for better integration
        nvim-lspconfig
        
        # Completion framework
        nvim-cmp
        cmp-nvim-lsp
        
        # Snippet support
        luasnip
        cmp_luasnip
      ];
      
      extraLuaConfig = ''
        -- GitHub Copilot configuration
        vim.g.copilot_enabled = ${if cfg.features.autoCompletion then "true" else "false"}
        vim.g.copilot_assume_mapped = true
        vim.g.copilot_tab_fallback = ""
        
        -- Copilot keybindings
        vim.keymap.set('i', '<C-J>', 'copilot#Accept("\\<CR>")', {
          expr = true,
          replace_keycodes = false
        })
        vim.keymap.set('i', '<C-K>', 'copilot#Previous()', { expr = true })
        vim.keymap.set('i', '<C-L>', 'copilot#Next()', { expr = true })
        vim.keymap.set('i', '<C-H>', 'copilot#Dismiss()', { expr = true })
        
        -- File type specific Copilot settings
        vim.api.nvim_create_autocmd("FileType", {
          pattern = { "nix", "sh", "bash", "yaml", "json", "markdown" },
          callback = function()
            vim.b.copilot_enabled = true
          end,
        })
        
        -- Disable Copilot for sensitive files
        vim.api.nvim_create_autocmd("BufRead", {
          pattern = { "*.env*", "*secret*", "*key*", "*.pem", "*.crt" },
          callback = function()
            vim.b.copilot_enabled = false
          end,
        })
        
        ${optionalString cfg.features.chatIntegration ''
        -- Copilot Chat setup (if plugin is available)
        -- require('copilot_cmp').setup()
        ''}
      '';
    };

    # Shell aliases and functions for Copilot CLI
    home-manager.users.yuki.programs.zsh.shellAliases = mkIf cfg.cli.enable {
      # GitHub Copilot CLI shortcuts
      "gcs" = "gh copilot suggest";
      "gce" = "gh copilot explain";
      "gcr" = "gh copilot review";
      
      # Copilot-specific development commands
      "copilot-suggest" = "gh copilot suggest";
      "copilot-explain" = "gh copilot explain";
      "copilot-review" = "gh copilot review";
    };

    home-manager.users.yuki.programs.zsh.initContent = mkIf cfg.cli.enable ''
      # GitHub Copilot CLI integration functions
      
      # Smart command suggestions
      copilot-cmd() {
        local description="$*"
        if [[ -z "$description" ]]; then
          echo "Usage: copilot-cmd <description of what you want to do>"
          echo "Example: copilot-cmd find all .nix files and format them"
          return 1
        fi
        
        echo "🤖 Getting command suggestion for: $description"
        gh copilot suggest "$description"
      }
      
      # Code explanation helper
      copilot-explain-file() {
        local file="$1"
        if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
          echo "Usage: copilot-explain-file <file>"
          return 1
        fi
        
        echo "🤖 Explaining file: $file"
        gh copilot explain --file "$file"
      }
      
      # Review current directory
      copilot-review-dir() {
        local dir="''${1:-.}"
        echo "🤖 Reviewing directory: $dir"
        
        # Get relevant files for review
        local files=$(find "$dir" -type f \( -name "*.nix" -o -name "*.sh" -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) | head -10)
        
        if [[ -n "$files" ]]; then
          echo "Files to review: $files"
          echo "$files" | while read -r file; do
            if [[ -f "$file" ]]; then
              echo "Reviewing: $file"
              gh copilot review --file "$file" || true
            fi
          done
        else
          echo "No suitable files found for review in $dir"
        fi
      }
      
      # Quick Git commit message generation
      copilot-commit-msg() {
        if ! git rev-parse --git-dir > /dev/null 2>&1; then
          echo "Not in a git repository"
          return 1
        fi
        
        local staged_files=$(git diff --cached --name-only)
        if [[ -z "$staged_files" ]]; then
          echo "No staged changes found. Stage some changes first with 'git add'"
          return 1
        fi
        
        echo "🤖 Generating commit message for staged changes..."
        echo "Staged files: $staged_files"
        
        local diff_summary=$(git diff --cached --stat)
        gh copilot suggest "Generate a conventional commit message for these changes: $diff_summary"
      }
      
      # Dotfiles-specific Copilot helpers
      copilot-nix-help() {
        local query="$*"
        if [[ -z "$query" ]]; then
          echo "Usage: copilot-nix-help <your Nix question>"
          echo "Example: copilot-nix-help how to add a new package to home-manager"
          return 1
        fi
        
        echo "🤖 Getting Nix help for: $query"
        gh copilot suggest "Nix/NixOS question: $query. Provide configuration examples for home-manager or nix-darwin."
      }
      
      copilot-dotfiles-improve() {
        echo "🤖 Getting dotfiles improvement suggestions..."
        cd "${config.home.homeDirectory}/dotfiles" || return 1
        
        gh copilot suggest "Analyze this dotfiles repository structure and suggest improvements for better organization, maintainability, and user experience"
      }
      
      ${optionalString cfg.features.commandSuggestions ''
      # Auto-suggest commands when typing "help" or "how"
      help() {
        if [[ $# -eq 0 ]]; then
          echo "🤖 Try: help <description of what you want to do>"
          echo "Example: help find large files in current directory"
        else
          copilot-cmd "$@"
        fi
      }
      
      how() {
        copilot-cmd "$@"
      }
      ''}
    '';

    # VSCode settings for Copilot (if using VSCode)
    home-manager.users.yuki.programs.vscode = mkIf cfg.editors.vscode.enable {
      extensions = with pkgs.vscode-extensions; [
        github.copilot
        github.copilot-chat
      ];
      
      userSettings = {
        "github.copilot.enable" = cfg.features.autoCompletion;
        "github.copilot.advanced" = {
          "listCount" = 10;
          "inlineSuggestCount" = 3;
        };
        
        # File type enablement
        "github.copilot.enabledLanguages" = {
          "nix" = true;
          "yaml" = true;
          "json" = true;
          "markdown" = true;
          "shellscript" = true;
          "bash" = true;
        };
        
        # Disable for sensitive files
        "files.associations" = {
          "*.env*" = "plaintext";
          "*secret*" = "plaintext";
          "*.key" = "plaintext";
          "*.pem" = "plaintext";
        };
        
        # Copilot Chat settings
        "github.copilot.chat.enabled" = cfg.features.chatIntegration;
      };
    };

    # Copilot-aware Git configuration
    home-manager.users.yuki.programs.git.extraConfig = mkIf cfg.features.codeReview {
      # Enable Copilot integration in Git
      copilot = {
        enabled = true;
      };
    };

    # Documentation and examples
    home-manager.users.yuki.home.file = {
      ".config/copilot/examples.md" = mkIf cfg.enable {
        text = ''
          # GitHub Copilot Usage Examples
          
          ## CLI Commands
          
          ### Get command suggestions:
          ```bash
          gcs "find all .nix files and format them"
          copilot-cmd "create a backup of all config files"
          ```
          
          ### Explain code:
          ```bash
          gce "nix-env -iA nixpkgs.vim"
          copilot-explain-file ./nix/flake.nix
          ```
          
          ### Review code:
          ```bash
          gcr --file ./scripts/install.sh
          copilot-review-dir ./nix/
          ```
          
          ## Neovim Integration
          
          ### Keybindings:
          - `Ctrl+J` - Accept suggestion
          - `Ctrl+K` - Previous suggestion  
          - `Ctrl+L` - Next suggestion
          - `Ctrl+H` - Dismiss suggestion
          
          ### Commands:
          - `:Copilot enable` - Enable Copilot
          - `:Copilot disable` - Disable Copilot
          - `:Copilot status` - Check status
          
          ## Dotfiles Specific Helpers
          
          ```bash
          copilot-nix-help "how to add a systemd service"
          copilot-commit-msg  # Generate commit message for staged changes
          copilot-dotfiles-improve  # Get improvement suggestions
          ```
          
          ## Best Practices
          
          1. Use specific, descriptive prompts
          2. Review suggestions before applying
          3. Disable for sensitive files (already configured)
          4. Use Copilot for learning Nix syntax
          5. Leverage for documentation and comments
        '';
      };
    };
  };
}