# Web開発環境 - GitHub Copilot統合
# VS Code、NeoVim、ターミナルでのGitHub Copilot活用

{ lib, pkgs, config, ... }:

let
  cfg = config.web.ai.copilot;
in
{
  options.web.ai.copilot = {
    enable = lib.mkEnableOption "GitHub Copilot integration";
    
    suggestions = lib.mkOption {
      type = lib.types.enum [ "conservative" "balanced" "aggressive" ];
      default = "balanced";
      description = "Copilot suggestion aggressiveness";
    };
    
    codeReview = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Copilot code review features";
    };
    
    docGeneration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic documentation generation";
    };
    
    testGeneration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable test case generation";
    };
    
    languages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "typescript"
        "javascript"
        "tsx"
        "jsx"
        "html"
        "css"
        "scss"
        "json"
        "markdown"
        "yaml"
        "rust"
        "python"
        "go"
        "bash"
      ];
      description = "Languages to enable Copilot for";
    };
    
    vscode = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable VS Code Copilot integration";
      };
      
      chatIntegration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Copilot Chat in VS Code";
      };
      
      inlineChat = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable inline chat features";
      };
    };
    
    neovim = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable NeoVim Copilot integration";
      };
      
      chatIntegration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Copilot Chat in NeoVim";
      };
    };
    
    cli = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable GitHub Copilot CLI";
      };
      
      aliases = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable shell aliases for Copilot CLI";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Install GitHub Copilot CLI
    home-manager.users.yuki.home.packages = with pkgs; lib.optionals cfg.cli.enable [
      github-copilot-cli
    ];
    
    # VS Code configuration
    home-manager.users.yuki.home.file.".vscode/copilot-settings.json" = lib.mkIf cfg.vscode.enable {
      text = builtins.toJSON {
        # Core Copilot settings
        "github.copilot.enable" = {
          "*" = true;
          "yaml" = true;
          "plaintext" = false;
          "markdown" = true;
        };
        
        # Language-specific settings
        "github.copilot.advanced" = builtins.listToAttrs (
          map (lang: {
            name = lang;
            value = {
              enable = true;
              suggestions = cfg.suggestions;
            };
          }) cfg.languages
        );
        
        # Suggestion behavior
        "github.copilot.inlineSuggest.enable" = true;
        "github.copilot.suggest.enable" = true;
        
        # Chat integration
        "github.copilot.chat.enable" = cfg.vscode.chatIntegration;
        "github.copilot.chat.inlineChat.enable" = cfg.vscode.inlineChat;
        
        # Editor integration
        "editor.inlineSuggest.enabled" = true;
        "editor.inlineSuggest.showToolbar" = "onHover";
        "editor.inlineSuggest.suppressSuggestions" = false;
        
        # Code actions
        "github.copilot.editor.enableCodeActions" = cfg.codeReview;
        "github.copilot.editor.enableAutoCompletions" = true;
        
        # Filtering and quality
        "github.copilot.advanced.suggestions.count" = 
          if cfg.suggestions == "conservative" then 1
          else if cfg.suggestions == "balanced" then 3
          else 5;
          
        "github.copilot.advanced.length" = 
          if cfg.suggestions == "conservative" then "small"
          else if cfg.suggestions == "balanced" then "medium"
          else "large";
          
        # Privacy and security
        "github.copilot.advanced.secretScanning.enable" = true;
        "github.copilot.advanced.filtering.enable" = true;
        
        # Telemetry
        "github.copilot.telemetry.enable" = false;
        
        # Workspace trust
        "security.workspace.trust.untrustedFiles" = "prompt";
      };
    };
    
    # NeoVim Copilot configuration
    home-manager.users.yuki.home.file.".config/nvim/lua/copilot-config.lua" = lib.mkIf cfg.neovim.enable {
      text = ''
        -- GitHub Copilot configuration for NeoVim
        
        -- Copilot.lua setup with safe loading
        local copilot_ok, copilot = pcall(require, 'copilot')
        if copilot_ok then
          copilot.setup({
          panel = {
            enabled = true,
            auto_refresh = true,
            keymap = {
              jump_prev = "[[",
              jump_next = "]]",
              accept = "<CR>",
              refresh = "gr",
              open = "<M-CR>"
            },
            layout = {
              position = "bottom",
              ratio = 0.4
            },
          },
          suggestion = {
            enabled = true,
            auto_trigger = ${if cfg.suggestions == "aggressive" then "true" else "false"},
            debounce = ${if cfg.suggestions == "conservative" then "150" else "75"},
            keymap = {
              accept = "<M-l>",
              accept_word = "<M-w>",
              accept_line = "<M-j>",
              next = "<M-]>",
              prev = "<M-[>",
              dismiss = "<C-]>",
            },
          },
          filetypes = {
            ${lib.concatMapStringsSep "\n    " (lang: "${lang} = true,") cfg.languages}
            ["*"] = false,
          },
          copilot_node_command = 'node',
          server_opts_overrides = {
            settings = {
              advanced = {
                listCount = ${
                  if cfg.suggestions == "conservative" then "1"
                  else if cfg.suggestions == "balanced" then "3" 
                  else "5"
                },
                inlineSuggestCount = ${
                  if cfg.suggestions == "conservative" then "1"
                  else if cfg.suggestions == "balanced" then "2"
                  else "3"
                },
              }
            }
          },
        })
        end
        
        ${lib.optionalString cfg.neovim.chatIntegration ''
        -- Copilot Chat setup with safe loading
        local copilot_chat_ok, copilot_chat = pcall(require, 'CopilotChat')
        if copilot_chat_ok then
          copilot_chat.setup({
          debug = false,
          model = 'gpt-4',
          temperature = 0.1,
          
          question_header = '## User ',
          answer_header = '## Copilot ',
          error_header = '## Error ',
          
          auto_follow_cursor = false,
          auto_insert_mode = true,
          clear_chat_on_new_prompt = false,
          highlight_selection = true,
          
          context = 'buffers',
          history_path = vim.fn.stdpath('data') .. '/copilot_chat_history',
          
          chat_autocomplete = true,
          
          mappings = {
            complete = {
              detail = 'Use @<Tab> or /<Tab> for options.',
              insert = '<Tab>',
            },
            close = {
              normal = 'q',
              insert = '<C-c>'
            },
            reset = {
              normal = '<C-l>',
              insert = '<C-l>'
            },
            submit_prompt = {
              normal = '<CR>',
              insert = '<C-m>'
            },
            accept_diff = {
              normal = '<C-y>',
              insert = '<C-y>'
            },
            yank_diff = {
              normal = 'gy',
            },
            show_diff = {
              normal = 'gd'
            },
            show_system_prompt = {
              normal = 'gp'
            },
            show_user_selection = {
              normal = 'gs'
            },
          },
        })
        end
        ''}
        
        -- Key mappings
        vim.keymap.set('i', '<C-J>', 'copilot#Accept("\\<CR>")', {
          expr = true,
          replace_keycodes = false
        })
        vim.g.copilot_no_tab_map = true
        
        -- Commands for productivity
        vim.api.nvim_create_user_command('CopilotToggle', function()
          if vim.b.copilot_enabled == false then
            vim.b.copilot_enabled = true
            print("Copilot enabled")
          else
            vim.b.copilot_enabled = false
            print("Copilot disabled")
          end
        end, {})
        
        ${lib.optionalString cfg.docGeneration ''
        -- Documentation generation
        vim.api.nvim_create_user_command('CopilotDoc', function()
          local prompt = "Generate comprehensive documentation for this function including parameters, return values, and usage examples:"
          require('CopilotChat').ask(prompt)
        end, {})
        ''}
        
        ${lib.optionalString cfg.testGeneration ''
        -- Test generation
        vim.api.nvim_create_user_command('CopilotTest', function()
          local prompt = "Generate comprehensive unit tests for this function including edge cases and error scenarios:"
          require('CopilotChat').ask(prompt)
        end, {})
        ''}
        
        ${lib.optionalString cfg.codeReview ''
        -- Code review
        vim.api.nvim_create_user_command('CopilotReview', function()
          local prompt = "Review this code for potential bugs, performance issues, and best practices:"
          require('CopilotChat').ask(prompt)
        end, {})
        ''}
      '';
    };
    
    # Shell aliases for Copilot CLI
    home-manager.users.yuki.home.shellAliases = lib.mkIf (cfg.cli.enable && cfg.cli.aliases) {
      # GitHub Copilot CLI shortcuts
      "copilot" = "gh copilot";
      "ai" = "gh copilot suggest";
      "ai-explain" = "gh copilot explain";
      
      # Quick AI commands
      "ai-git" = "gh copilot suggest -t git";
      "ai-shell" = "gh copilot suggest -t shell";
      "ai-gh" = "gh copilot suggest -t gh";
      
      # Code assistance
      "explain" = "gh copilot explain";
      "suggest" = "gh copilot suggest";
    };
    
    # GitHub CLI configuration for Copilot
    home-manager.users.yuki.home.file.".config/gh/config.yml" = {
      text = lib.generators.toYAML {} {
        version = 1;
        
        aliases = lib.mkIf cfg.cli.aliases {
          ai = "copilot suggest";
          explain = "copilot explain";
        };
        
        # Copilot configuration
        copilot = {
          enable = cfg.cli.enable;
        };
        
        # Editor preference
        editor = "nvim";
        
        # Git protocol
        git_protocol = "ssh";
        
        # Browser
        browser = "default";
      };
    };
    
    # Copilot health check script
    home-manager.users.yuki.home.file."bin/copilot-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🤖 GitHub Copilot Health Check"
        echo "=============================="
        
        # Check GitHub CLI
        if command -v gh &> /dev/null; then
          echo "✅ GitHub CLI: $(gh --version | head -n1)"
          
          # Check authentication
          if gh auth status &> /dev/null; then
            echo "✅ GitHub authentication: active"
          else
            echo "❌ GitHub authentication: required"
            echo "   Run: gh auth login"
          fi
          
          # Check Copilot subscription
          if gh copilot --help &> /dev/null; then
            echo "✅ Copilot CLI: available"
          else
            echo "❌ Copilot CLI: not available"
            echo "   Check your Copilot subscription"
          fi
        else
          echo "❌ GitHub CLI: not found"
        fi
        
        echo ""
        echo "🔧 Editor Integration:"
        
        # Check VS Code
        ${lib.optionalString cfg.vscode.enable ''
        if command -v code &> /dev/null; then
          echo "✅ VS Code: available"
          if code --list-extensions | grep -q "github.copilot"; then
            echo "✅ VS Code Copilot extension: installed"
          else
            echo "❌ VS Code Copilot extension: not installed"
            echo "   Install: code --install-extension github.copilot"
          fi
        else
          echo "⚪ VS Code: not found"
        fi
        ''}
        
        # Check NeoVim
        ${lib.optionalString cfg.neovim.enable ''
        if command -v nvim &> /dev/null; then
          echo "✅ NeoVim: available"
          if [[ -f ~/.config/nvim/lua/copilot-config.lua ]]; then
            echo "✅ NeoVim Copilot config: present"
          else
            echo "❌ NeoVim Copilot config: missing"
          fi
        else
          echo "⚪ NeoVim: not found"
        fi
        ''}
        
        echo ""
        echo "📊 Configuration:"
        echo "Suggestion level: ${cfg.suggestions}"
        echo "Code review: ${if cfg.codeReview then "enabled" else "disabled"}"
        echo "Doc generation: ${if cfg.docGeneration then "enabled" else "disabled"}"
        echo "Test generation: ${if cfg.testGeneration then "enabled" else "disabled"}"
        echo "Supported languages: ${toString cfg.languages}"
        
        echo ""
        echo "✅ Copilot health check completed!"
      '';
    };
  };
}