# AI CLI Integration Tools
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.ai-platform.cli;
in
{
  options.dotfiles.development.ai-platform.cli = {
    enable = mkEnableOption "AI CLI integration tools";
    
    shellGpt = mkOption {
      type = types.bool;
      default = true;
      description = "Enable shell-gpt for command line AI assistance";
    };
    
    mods = mkOption {
      type = types.bool;
      default = true;
      description = "Enable mods for AI-powered command suggestions";
    };
    
    aiCommit = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI-powered commit message generation";
    };
    
    explainShell = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI command explanation";
    };
  };

  config = mkIf cfg.enable {
    # CLI AI tools installation and setup
    home-manager.users.yuki.home.file."bin/ai-cli-setup" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # AI CLI Integration Setup
        set -euo pipefail
        
        echo "🤖 Setting up AI CLI Integration Tools"
        echo "====================================="
        
        # Install shell-gpt
        ${if cfg.shellGpt then ''
          echo "📦 Installing shell-gpt..."
          if command -v pip &> /dev/null; then
            pip install --user shell-gpt
            echo "✅ shell-gpt installed"
          else
            echo "⚠️  pip not found, skipping shell-gpt"
          fi
        '' else ''
          echo "📦 shell-gpt: Disabled"
        ''}
        
        # Install mods
        ${if cfg.mods then ''
          echo "📦 Installing mods..."
          if command -v npm &> /dev/null; then
            npm install -g mods-cli
            echo "✅ mods installed"
          elif command -v go &> /dev/null; then
            go install github.com/charmbracelet/mods@latest
            echo "✅ mods installed via Go"
          else
            echo "⚠️  npm/go not found, skipping mods"
          fi
        '' else ''
          echo "📦 mods: Disabled"
        ''}
        
        # Setup AI commit
        ${if cfg.aiCommit then ''
          echo "📦 Setting up AI commit..."
          if command -v npm &> /dev/null; then
            npm install -g @commitlint/cli @commitlint/config-conventional
            echo "✅ AI commit tools installed"
          else
            echo "⚠️  npm not found, skipping AI commit setup"
          fi
        '' else ''
          echo "📦 AI commit: Disabled"
        ''}
        
        echo ""
        echo "🎉 AI CLI Integration setup complete!"
        echo ""
        echo "🔧 Available Commands:"
        echo "  sgpt <query>           - Ask AI anything"
        echo "  mods <query>          - AI-powered command suggestions"
        echo "  ai-commit             - Generate commit messages"
        echo "  explain-cmd <command> - Explain shell commands"
        echo "  fix-cmd <error>       - Fix command errors"
      '';
    };

    # Smart shell GPT wrapper
    home-manager.users.yuki.home.file."bin/sgpt-local" = mkIf cfg.shellGpt {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Smart shell-gpt wrapper with Ollama fallback
        set -euo pipefail
        
        QUERY="$*"
        
        # Prefer local Ollama if available
        if command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
          echo "🤖 Using local Ollama..."
          ollama-manager chat codellama "$QUERY"
        elif command -v sgpt &> /dev/null; then
          echo "🤖 Using shell-gpt..."
          sgpt "$QUERY"
        else
          echo "❌ No AI tools available"
          echo "💡 Setup: ai-cli-setup or ollama-manager setup"
          exit 1
        fi
      '';
    };

    # AI-powered commit message generator
    home-manager.users.yuki.home.file."bin/ai-commit" = mkIf cfg.aiCommit {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # AI-Powered Commit Message Generator
        set -euo pipefail
        
        # Check if we're in a git repository
        if ! git rev-parse --git-dir > /dev/null 2>&1; then
          echo "❌ Not in a git repository"
          exit 1
        fi
        
        # Check for staged changes
        if ! git diff --cached --quiet; then
          echo "🔍 Analyzing staged changes..."
          
          # Get the diff of staged changes
          DIFF=$(git diff --cached)
          
          # Create AI prompt for commit message
          PROMPT="Based on the following git diff, generate a concise, clear commit message following conventional commits format.
        
        Rules:
        1. Use format: type(scope): description
        2. Types: feat, fix, docs, style, refactor, test, chore
        3. Keep under 50 characters for the subject line
        4. Be specific and descriptive
        5. Use imperative mood (Add, Fix, Update, etc.)
        
        Git diff:
        $DIFF
        
        Generate only the commit message, nothing else:"
          
          echo "🤖 Generating commit message..."
          
          # Use available AI tools
          if command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
            COMMIT_MSG=$(echo "$PROMPT" | ollama-manager chat codellama | tail -1)
          elif command -v sgpt &> /dev/null; then
            COMMIT_MSG=$(echo "$PROMPT" | sgpt)
          else
            echo "❌ No AI tools available for commit message generation"
            echo "💡 Setup: ai-cli-setup or ollama-manager setup"
            exit 1
          fi
          
          # Clean up the commit message
          COMMIT_MSG=$(echo "$COMMIT_MSG" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
          
          echo ""
          echo "📝 Generated commit message:"
          echo "   $COMMIT_MSG"
          echo ""
          
          # Ask for confirmation
          read -p "Use this commit message? (y/N): " -r
          if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            git commit -m "$COMMIT_MSG"
            echo "✅ Commit created successfully"
          else
            echo "ℹ️  Commit cancelled"
          fi
        else
          echo "⚠️  No staged changes to commit"
          echo "💡 Stage changes with: git add <files>"
        fi
      '';
    };

    # Command explanation tool
    home-manager.users.yuki.home.file."bin/explain-cmd" = mkIf cfg.explainShell {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # AI Command Explanation Tool
        set -euo pipefail
        
        COMMAND="$*"
        
        if [[ -z "$COMMAND" ]]; then
          echo "Usage: explain-cmd <command>"
          echo "Example: explain-cmd 'find . -name \"*.js\" -exec grep -l \"function\" {} \;'"
          exit 1
        fi
        
        PROMPT="Explain this shell command in detail:
        
        Command: $COMMAND
        
        Please explain:
        1. What this command does overall
        2. Break down each part/option
        3. What the output would be
        4. Any potential risks or side effects
        5. Common use cases
        
        Make it beginner-friendly but comprehensive."
        
        echo "🤖 Explaining command: $COMMAND"
        echo "=================================="
        echo ""
        
        # Use available AI tools
        if command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
          echo "$PROMPT" | ollama-manager chat codellama
        elif command -v sgpt &> /dev/null; then
          echo "$PROMPT" | sgpt
        else
          echo "❌ No AI tools available for command explanation"
          echo "💡 Setup: ai-cli-setup or ollama-manager setup"
          exit 1
        fi
      '';
    };

    # Command error fixing tool
    home-manager.users.yuki.home.file."bin/fix-cmd" = mkIf cfg.explainShell {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # AI Command Error Fixing Tool
        set -euo pipefail
        
        ERROR_MSG="$*"
        
        if [[ -z "$ERROR_MSG" ]]; then
          echo "Usage: fix-cmd <error_message>"
          echo "Example: fix-cmd 'command not found: python'"
          exit 1
        fi
        
        # Get recent command history for context
        RECENT_COMMANDS=$(history | tail -5 | cut -c 8-)
        
        PROMPT="Help me fix this command error:
        
        Error: $ERROR_MSG
        
        Recent commands for context:
        $RECENT_COMMANDS
        
        Please provide:
        1. Explanation of what went wrong
        2. Specific solution/fix
        3. Corrected command to run
        4. How to prevent this error in the future
        
        Be concise and actionable."
        
        echo "🔧 Analyzing error: $ERROR_MSG"
        echo "==============================="
        echo ""
        
        # Use available AI tools
        if command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
          echo "$PROMPT" | ollama-manager chat codellama
        elif command -v sgpt &> /dev/null; then
          echo "$PROMPT" | sgpt
        else
          echo "❌ No AI tools available for error fixing"
          echo "💡 Setup: ai-cli-setup or ollama-manager setup"
          exit 1
        fi
      '';
    };

    # Smart command suggestions
    home-manager.users.yuki.home.file."bin/suggest-cmd" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # AI Command Suggestion Tool
        set -euo pipefail
        
        TASK="$*"
        
        if [[ -z "$TASK" ]]; then
          echo "Usage: suggest-cmd <what you want to do>"
          echo "Example: suggest-cmd 'find all large files in home directory'"
          exit 1
        fi
        
        # Get current directory and system info for context
        CURRENT_DIR=$(pwd)
        SYSTEM_INFO=$(uname -s)
        
        PROMPT="Suggest shell commands for this task: $TASK
        
        Context:
        - Current directory: $CURRENT_DIR
        - System: $SYSTEM_INFO
        - Shell: zsh
        
        Please provide:
        1. Most common/recommended approach
        2. Alternative methods if applicable
        3. Brief explanation of each command
        4. Any warnings or considerations
        
        Format as executable commands with explanations."
        
        echo "💡 Suggesting commands for: $TASK"
        echo "=================================="
        echo ""
        
        # Use available AI tools
        if command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
          echo "$PROMPT" | ollama-manager chat codellama
        elif command -v sgpt &> /dev/null; then
          echo "$PROMPT" | sgpt
        else
          echo "❌ No AI tools available for command suggestions"
          echo "💡 Setup: ai-cli-setup or ollama-manager setup"
          exit 1
        fi
      '';
    };

    # Shell aliases for AI CLI tools
    home-manager.users.yuki.programs.zsh.shellAliases = mkMerge [
      (mkIf cfg.shellGpt {
        ask = "sgpt-local";
        ai = "sgpt-local";
      })
      
      (mkIf cfg.explainShell {
        explain = "explain-cmd";
        fix = "fix-cmd";
        suggest = "suggest-cmd";
      })
      
      (mkIf cfg.aiCommit {
        gaic = "ai-commit";  # git ai commit
        gencmt = "ai-commit";  # generate commit
      })
      
      # General AI helpers
      {
        "?" = "suggest-cmd";  # Quick command suggestion
        "??" = "explain-cmd \$(fc -ln -1)";  # Explain last command
      }
    ];

    # Zsh integration for enhanced AI assistance
    home-manager.users.yuki.programs.zsh.initContent = ''
      # AI CLI Integration
      
      # Function to get AI help for failed commands
      ai_help_failed() {
        local exit_code=$?
        if [[ $exit_code -ne 0 ]] && [[ -n "''${ZSH_AI_HELP:-}" ]]; then
          local last_cmd="$(fc -ln -1)"
          echo ""
          echo "💡 Command failed. Getting AI help..."
          fix-cmd "Command '$last_cmd' failed with exit code $exit_code"
        fi
        return $exit_code
      }
      
      # Function to explain commands before execution (when enabled)
      ai_explain_before() {
        if [[ -n "''${ZSH_AI_EXPLAIN:-}" ]]; then
          local cmd="$1"
          if [[ "$cmd" =~ ^(rm|mv|cp|chmod|chown|sudo|su|dd|mkfs|fdisk|parted).* ]]; then
            echo "⚠️  Potentially dangerous command detected!"
            explain-cmd "$cmd"
            read -q "REPLY?Continue? (y/N): "
            if [[ "$REPLY" != "y" ]]; then
              return 1
            fi
          fi
        fi
      }
      
      # Enable AI help on failed commands (optional)
      # export ZSH_AI_HELP=1
      
      # Enable AI explanation for dangerous commands (optional)
      # export ZSH_AI_EXPLAIN=1
      
      # Aliases for enabling/disabling AI features
      alias ai-help-on="export ZSH_AI_HELP=1"
      alias ai-help-off="unset ZSH_AI_HELP"
      alias ai-explain-on="export ZSH_AI_EXPLAIN=1"
      alias ai-explain-off="unset ZSH_AI_EXPLAIN"
    '';

    # Environment variables
    home-manager.users.yuki.home.sessionVariables = {
      AI_CLI_ENABLED = "true";
      SGPT_LOCAL_BACKEND = "ollama";  # Prefer local backend
    };
  };
}