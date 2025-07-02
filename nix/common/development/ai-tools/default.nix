{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.ai-tools;
in
{
  options.dotfiles.development.ai-tools = {
    enable = mkEnableOption "AI development tools support";
    
    copilotSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable GitHub Copilot support";
    };
    
    codeiumSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Codeium support";
    };
    
    claudeSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Claude Code support";
    };

    geminiSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Gemini CLI support";
    };
    
    claudeNotifications = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Claude Code notifications";
    };
    
    cursorSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Cursor editor support";
    };
    
    mcpSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Model Context Protocol support";
    };
    
    nvimAiIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI tools integration in Neovim";
    };
    
    vscodeAiIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI tools integration in VS Code";
    };
  };

  config = mkIf cfg.enable {
    # AI-powered development packages
    home-manager.users.yuki.home.packages = with pkgs; [
      # AI CLI tools
      aichat
      chatgpt-cli
      
      # Code generation and completion
      github-cli  # For Copilot CLI
      
      # AI-powered development tools
    ] ++ optionals cfg.geminiSupport [
      gemini-cli
    ] ++ optionals cfg.mcpSupport [
      # MCP-related tools
      nodejs
      nodePackages.npm
    ] ++ optionals cfg.claudeNotifications [
      # Claude Code notifications
      terminal-notifier
      jq
    ];

    # Neovim AI integration
    home-manager.users.yuki.programs.neovim = mkIf cfg.nvimAiIntegration {
      plugins = with pkgs.vimPlugins; [
        # GitHub Copilot
        copilot-vim
        copilot-lua
        copilot-cmp
        
        # ChatGPT/AI integration
        ChatGPT-nvim
        
        # Code assistance
        nvim-cmp
        cmp-ai
      ];
      
      extraLuaConfig = mkIf cfg.copilotSupport ''
        -- GitHub Copilot configuration
        require('copilot').setup({
          suggestion = {
            enabled = true,
            auto_trigger = true,
            debounce = 75,
            keymap = {
              accept = "<M-l>",
              accept_word = false,
              accept_line = false,
              next = "<M-]>",
              prev = "<M-[>",
              dismiss = "<C-]>",
            },
          },
          filetypes = {
            yaml = false,
            markdown = false,
            help = false,
            gitcommit = false,
            gitrebase = false,
            hgcommit = false,
            svn = false,
            cvs = false,
            ["."] = false,
          },
          copilot_node_command = '${pkgs.nodejs}/bin/node',
        })
        
        -- Copilot CMP integration
        require('copilot_cmp').setup()
        
        -- ChatGPT configuration
        require("chatgpt").setup({
          api_key_cmd = "echo $OPENAI_API_KEY",
          yank_register = "+",
          edit_with_instructions = {
            diff = false,
            keymaps = {
              close = "<C-c>",
              accept = "<C-y>",
              toggle_diff = "<C-d>",
              toggle_settings = "<C-o>",
              cycle_windows = "<Tab>",
              use_output_as_input = "<C-i>",
            },
          },
          chat = {
            welcome_message = "Welcome to ChatGPT",
            loading_text = "Loading, please wait ...",
            question_sign = "",
            answer_sign = "ﮧ",
            max_line_length = 120,
            sessions_window = {
              border = {
                style = "rounded",
                text = {
                  top = " Sessions ",
                },
              },
            },
          },
        })
      '';
    };

    # VS Code AI extensions configuration
    home-manager.users.yuki.home.file.".vscode/ai-settings.json" = mkIf cfg.vscodeAiIntegration {
      text = builtins.toJSON {
        # GitHub Copilot settings
        "github.copilot.enable" = cfg.copilotSupport;
        "github.copilot.inlineSuggest.enable" = cfg.copilotSupport;
        "github.copilot.editor.enableAutoCompletions" = cfg.copilotSupport;
        
        # Codeium settings
        "codeium.enableCodeLens" = cfg.codeiumSupport;
        "codeium.enableConfig" = cfg.codeiumSupport;
        
        # Claude Code settings
        "claude.enabled" = cfg.claudeSupport;
        "claude.autoSave" = true;
        
        # General AI settings
        "editor.inlineSuggest.enabled" = true;
        "editor.suggestSelection" = "first";
        "editor.acceptSuggestionOnCommitCharacter" = false;
        "editor.acceptSuggestionOnEnter" = "on";
      };
    };

    # MCP server configuration for Claude (file-based configuration)
    home-manager.users.yuki.home.file.".config/mcp/install-packages.sh" = mkIf cfg.mcpSupport {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # MCP global packages installation script
        set -euo pipefail
        
        echo "📦 Installing MCP global packages..."
        npm install -g \
          "@modelcontextprotocol/server-filesystem" \
          "@modelcontextprotocol/server-postgres" \
          "@modelcontextprotocol/server-github" \
          "@modelcontextprotocol/server-brave-search" \
          "@modelcontextprotocol/server-puppeteer" \
          "@executeautomation/playwright-mcp-server"
        
        echo "✅ MCP packages installed successfully!"
      '';
    };

    # AI tools aliases and commands
    home-manager.users.yuki.programs.zsh.shellAliases = {
      ai-chat = "aichat";
      copilot = "gh copilot";
      ai-commit = "gh copilot suggest -t shell 'git commit with AI-generated message'";
      ai-explain = "gh copilot explain";
      install-mcp = "~/.config/mcp/install-packages.sh";
    };
    # Disabled claude notifications aliases - files not present
    # } // optionalAttrs cfg.claudeNotifications {
    #   claude-notify = "~/.dotfiles/configs/apps/claude/claude-notifications.sh";
    #   claude-monitor = "~/.dotfiles/configs/apps/claude/claude-notifications.sh monitor";
    #   claude-test = "~/.dotfiles/configs/apps/claude/claude-notifications.sh test";
    # };

    # Environment variables for AI tools
    home-manager.users.yuki.home.sessionVariables = {
      # GitHub Copilot
      GITHUB_COPILOT_CLI_EDITOR = "nvim";
    };

    # MCP configuration for Claude (simple template)
    home-manager.users.yuki.home.file.".config/claude/claude.json.example" = mkIf cfg.mcpSupport {
      text = builtins.toJSON {
        mcpServers = {
          filesystem = {
            command = "npx";
            args = [ "@modelcontextprotocol/server-filesystem" ];
            env = {
              NPM_CONFIG_CACHE = "$HOME/.cache/npm";
            };
          };
          github = {
            command = "npx";
            args = [ "@modelcontextprotocol/server-github" ];
            env = {
              GITHUB_PERSONAL_ACCESS_TOKEN = "$GITHUB_TOKEN";
            };
          };
        };
      };
    };

    # Claude Code notifications configuration (disabled - files not present)
    # home-manager.users.yuki.home.file.".dotfiles/configs/apps/claude/claude-notifications.sh" = mkIf cfg.claudeNotifications {
    #   source = ../../configs/apps/claude/claude-notifications.sh;
    #   executable = true;
    # };

    # home-manager.users.yuki.home.file.".dotfiles/configs/apps/claude/notification-config.json" = mkIf cfg.claudeNotifications {
    #   source = ../../configs/apps/claude/notification-config.json;
    # };

    # AI development templates
    home-manager.users.yuki.home.file."bin/ai-project-init" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # AI-powered project initialization
        set -euo pipefail
        
        PROJECT_NAME="$1"
        PROJECT_TYPE="''${2:-general}"
        
        echo "🤖 Initializing AI-powered development environment for: $PROJECT_NAME"
        
        mkdir -p "$PROJECT_NAME"
        cd "$PROJECT_NAME"
        
        # Create .devcontainer if containers are enabled
        if command -v docker &> /dev/null; then
          mkdir -p .devcontainer
          cat > .devcontainer/devcontainer.json << 'EOF'
        {
          "name": "'"$PROJECT_NAME"' Development",
          "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
          "features": {
            "ghcr.io/devcontainers/features/github-cli:1": {},
            "ghcr.io/devcontainers/features/node:1": {},
            "ghcr.io/devcontainers/features/python:1": {}
          },
          "customizations": {
            "vscode": {
              "extensions": [
                "GitHub.copilot",
                "GitHub.copilot-chat",
                "ms-vscode-remote.remote-containers"
              ]
            }
          },
          "postCreateCommand": "echo 'AI development environment ready!'"
        }
        EOF
        fi
        
        # Create AI-friendly project structure
        cat > README.md << 'EOF'
        # '"$PROJECT_NAME"'
        
        AI-powered development project initialized with Claude Code.
        
        ## Development Setup
        
        This project is configured for AI-assisted development with:
        - GitHub Copilot integration
        - Dev Containers support
        - MCP (Model Context Protocol) ready
        
        ## Getting Started
        
        1. Open in VS Code with Dev Containers extension
        2. Or use `nix develop` for local development
        3. AI tools are pre-configured and ready to use
        
        EOF
        
        # Create shell.nix for Nix development
        cat > shell.nix << 'EOF'
        { pkgs ? import <nixpkgs> {} }:
        
        pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs
            python3
            git
            github-cli
          ];
          
          shellHook = '''
            echo "🚀 AI-powered development environment activated!"
            echo "Available tools: node, python3, git, gh"
          ''';
        }
        EOF
        
        echo "✅ AI-powered project '$PROJECT_NAME' initialized!"
        echo "📁 Directory: $(pwd)"
        echo "🛠️  Next steps:"
        echo "   1. cd $PROJECT_NAME"
        echo "   2. code . (for VS Code with AI tools)"
        echo "   3. nix develop (for Nix shell)"
      '';
    };

    # AI tools health check
    home-manager.users.yuki.home.file."bin/ai-tools-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🤖 AI Tools Health Check"
        echo "========================"
        
        # Check GitHub Copilot
        ${if cfg.copilotSupport then ''
          if gh copilot --help &> /dev/null; then
            echo "✅ GitHub Copilot CLI: Available"
          else
            echo "❌ GitHub Copilot CLI: Not available"
          fi
        '' else ''
          echo "⚪ GitHub Copilot: Disabled"
        ''}
        
        # Check AI chat tools
        if command -v aichat &> /dev/null; then
          echo "✅ AI Chat: Available"
        else
          echo "❌ AI Chat: Not available"
        fi
        
        # Check Claude notifications
        ${if cfg.claudeNotifications then ''
          if command -v terminal-notifier &> /dev/null; then
            echo "✅ Claude Notifications: terminal-notifier available"
          else
            echo "❌ Claude Notifications: terminal-notifier not available"
          fi
          
          if [[ -x "$HOME/.dotfiles/configs/apps/claude/claude-notifications.sh" ]]; then
            echo "✅ Claude Notifications: Script available"
          else
            echo "❌ Claude Notifications: Script not found or not executable"
          fi
        '' else ''
          echo "⚪ Claude Notifications: Disabled"
        ''}
        
        # Check MCP support
        ${if cfg.mcpSupport then ''
          if command -v npm &> /dev/null; then
            echo "✅ MCP Support: Node.js available"
          else
            echo "❌ MCP Support: Node.js not available"
          fi
        '' else ''
          echo "⚪ MCP Support: Disabled"
        ''}
        
        # Check environment variables
        echo ""
        echo "🔑 Environment Variables:"
        if [[ -n "''${GITHUB_TOKEN:-}" ]]; then
          echo "✅ GITHUB_TOKEN: Set"
        else
          echo "⚠️  GITHUB_TOKEN: Not set (needed for GitHub Copilot)"
        fi
        
        if [[ -n "''${OPENAI_API_KEY:-}" ]]; then
          echo "✅ OPENAI_API_KEY: Set"
        else
          echo "⚪ OPENAI_API_KEY: Not set (optional for ChatGPT)"
        fi
        
        if [[ -n "''${ANTHROPIC_API_KEY:-}" ]]; then
          echo "✅ ANTHROPIC_API_KEY: Set"
        else
          echo "⚪ ANTHROPIC_API_KEY: Not set (optional for Claude)"
        fi
      '';
    };
  };
}