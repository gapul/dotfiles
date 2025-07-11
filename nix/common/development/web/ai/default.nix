# Web開発環境 - AI統合モジュール
# GitHub Copilot、エディターAI、v0.dev統合の統合管理

{ lib, pkgs, config, ... }:

with lib;

{
  imports = [
    ./github-copilot.nix
    ./editor-ai.nix
  ];

  options.web.ai = {
    enable = mkEnableOption "Web development AI integrations";
    
    profile = mkOption {
      type = types.enum [ "basic" "standard" "advanced" "experimental" ];
      default = "standard";
      description = "AI integration profile";
    };
    
    privacy = {
      enableTelemetry = mkOption {
        type = types.bool;
        default = false;
        description = "Enable telemetry for AI services";
      };
      
      localModels = mkOption {
        type = types.bool;
        default = false;
        description = "Prefer local AI models when available";
      };
      
      dataRetention = mkOption {
        type = types.enum [ "none" "session" "minimal" "standard" ];
        default = "minimal";
        description = "Data retention policy for AI services";
      };
    };
    
    performance = {
      enableCaching = mkOption {
        type = types.bool;
        default = true;
        description = "Enable AI response caching";
      };
      
      maxConcurrentRequests = mkOption {
        type = types.int;
        default = 3;
        description = "Maximum concurrent AI requests";
      };
      
      timeout = mkOption {
        type = types.int;
        default = 30;
        description = "AI request timeout in seconds";
      };
    };
  };

  config = mkIf config.web.ai.enable {
    # Enable core AI components
    web.ai.copilot.enable = mkDefault true;
    web.ai.editor.enable = mkDefault true;
    
    # Profile-specific configurations
    web.ai.copilot = mkMerge [
      (mkIf (config.web.ai.profile == "basic") {
        suggestions = mkDefault "conservative";
        codeReview = mkDefault false;
        testGeneration = mkDefault false;
        cli.enable = mkDefault false;
      })
      (mkIf (config.web.ai.profile == "standard") {
        suggestions = mkDefault "balanced";
        codeReview = mkDefault true;
        testGeneration = mkDefault true;
        cli.enable = mkDefault true;
      })
      (mkIf (elem config.web.ai.profile [ "advanced" "experimental" ]) {
        suggestions = mkDefault "aggressive";
        codeReview = mkDefault true;
        docGeneration = mkDefault true;
        testGeneration = mkDefault true;
        cli.enable = mkDefault true;
      })
    ];
    
    web.ai.editor = mkMerge [
      (mkIf (config.web.ai.profile == "basic") {
        vscode.extensions = mkDefault [ "cursor" ];
        neovim.plugins = mkDefault [ "codeium" ];
        features.codeGeneration = mkDefault false;
        features.refactoring = mkDefault false;
      })
      (mkIf (config.web.ai.profile == "standard") {
        vscode.extensions = mkDefault [ "cursor" "claude-dev" ];
        neovim.plugins = mkDefault [ "neural" "codeium" ];
        features = {
          codeCompletion = mkDefault true;
          codeGeneration = mkDefault true;
          codeExplanation = mkDefault true;
          refactoring = mkDefault false;
          testGeneration = mkDefault true;
          documentation = mkDefault true;
        };
      })
      (mkIf (config.web.ai.profile == "advanced") {
        vscode.extensions = mkDefault [ "cursor" "claude-dev" "continue" "codeium" ];
        neovim.plugins = mkDefault [ "neural" "chatgpt" "codeium" "cmp-ai" ];
        features = {
          codeCompletion = mkDefault true;
          codeGeneration = mkDefault true;
          codeExplanation = mkDefault true;
          refactoring = mkDefault true;
          testGeneration = mkDefault true;
          documentation = mkDefault true;
        };
      })
      (mkIf (config.web.ai.profile == "experimental") {
        vscode.extensions = mkDefault [ "cursor" "claude-dev" "continue" "codeium" "tabnine" ];
        neovim.plugins = mkDefault [ "neural" "chatgpt" "codeium" "tabnine" "cmp-ai" ];
        features = {
          codeCompletion = mkDefault true;
          codeGeneration = mkDefault true;
          codeExplanation = mkDefault true;
          refactoring = mkDefault true;
          testGeneration = mkDefault true;
          documentation = mkDefault true;
        };
      })
    ];
    
    # Privacy-focused configurations
    home-manager.users.yuki.home.sessionVariables = mkMerge [
      {
        AI_TELEMETRY_ENABLED = if config.web.ai.privacy.enableTelemetry then "1" else "0";
        AI_LOCAL_MODELS = if config.web.ai.privacy.localModels then "1" else "0";
        AI_DATA_RETENTION = config.web.ai.privacy.dataRetention;
      }
      
      # Performance settings
      {
        AI_CACHE_ENABLED = if config.web.ai.performance.enableCaching then "1" else "0";
        AI_MAX_CONCURRENT = toString config.web.ai.performance.maxConcurrentRequests;
        AI_TIMEOUT = toString config.web.ai.performance.timeout;
      }
    ];
    
    # AI cache directory
    home-manager.users.yuki.home.file.".ai-cache/.gitignore" = mkIf config.web.ai.performance.enableCaching {
      text = ''
        # AI cache directory
        *
        !.gitignore
      '';
    };
    
    # Global AI configuration
    home-manager.users.yuki.home.file.".config/ai-config.json" = {
      text = builtins.toJSON {
        profile = config.web.ai.profile;
        
        privacy = {
          telemetry = config.web.ai.privacy.enableTelemetry;
          localModels = config.web.ai.privacy.localModels;
          dataRetention = config.web.ai.privacy.dataRetention;
        };
        
        performance = {
          caching = config.web.ai.performance.enableCaching;
          maxConcurrentRequests = config.web.ai.performance.maxConcurrentRequests;
          timeout = config.web.ai.performance.timeout;
        };
        
        services = {
          copilot = config.web.ai.copilot.enable;
          editor = config.web.ai.editor.enable;
        };
        
        features = {
          codeCompletion = config.web.ai.editor.features.codeCompletion;
          codeGeneration = config.web.ai.editor.features.codeGeneration;
          codeExplanation = config.web.ai.editor.features.codeExplanation;
          refactoring = config.web.ai.editor.features.refactoring;
          testGeneration = config.web.ai.editor.features.testGeneration;
          documentation = config.web.ai.editor.features.documentation;
        };
      };
    };
    
    # AI workflow scripts
    home-manager.users.yuki.home.file."bin/ai-workflow" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        show_usage() {
          cat << EOF
        Usage: ai-workflow <command> [options]
        
        COMMANDS:
          setup           Setup AI development workflow
          generate        Generate code from description
          explain         Explain selected code
          refactor        Refactor selected code
          test            Generate tests for code
          document        Generate documentation
          review          Review code with AI
          optimize        Optimize code performance
          
        OPTIONS:
          --model MODEL   Specify AI model (gpt-4, claude-3, etc.)
          --file FILE     Target file for operations
          --interactive   Interactive mode
          --output FILE   Output file for generated content
          
        EXAMPLES:
          ai-workflow setup
          ai-workflow generate --interactive
          ai-workflow explain --file src/utils.ts
          ai-workflow test --file src/component.tsx
        EOF
        }
        
        setup_workflow() {
          echo "🤖 Setting up AI development workflow..."
          
          # Check authentication
          if ! gh auth status &> /dev/null; then
            echo "Setting up GitHub authentication..."
            gh auth login
          fi
          
          # Check Copilot subscription
          if ! gh copilot --help &> /dev/null; then
            echo "⚠️  GitHub Copilot subscription required"
            echo "Visit: https://github.com/features/copilot"
            exit 1
          fi
          
          # Setup VS Code extensions
          if command -v code &> /dev/null; then
            echo "Installing VS Code AI extensions..."
            ${lib.concatMapStringsSep "\n            " (ext:
              if ext == "cursor" then ''echo "Cursor requires separate installation"''
              else if ext == "claude-dev" then ''code --install-extension saoudrizwan.claude-dev''
              else if ext == "continue" then ''code --install-extension continue.continue''
              else if ext == "codeium" then ''code --install-extension codeium.codeium''
              else if ext == "tabnine" then ''code --install-extension tabnine.tabnine-vscode''
              else ""
            ) config.web.ai.editor.vscode.extensions}
          fi
          
          echo "✅ AI workflow setup completed!"
        }
        
        generate_code() {
          local description="$1"
          local output_file="''${2:-}"
          
          echo "🔄 Generating code: $description"
          
          if [[ -n "$output_file" ]]; then
            gh copilot suggest --type shell "Generate code for: $description" > "$output_file"
            echo "✅ Code generated in: $output_file"
          else
            gh copilot suggest --type shell "Generate code for: $description"
          fi
        }
        
        explain_code() {
          local file="$1"
          
          if [[ ! -f "$file" ]]; then
            echo "❌ File not found: $file"
            exit 1
          fi
          
          echo "🔍 Explaining code in: $file"
          gh copilot explain "$(cat "$file")"
        }
        
        generate_tests() {
          local file="$1"
          
          if [[ ! -f "$file" ]]; then
            echo "❌ File not found: $file"
            exit 1
          fi
          
          echo "🧪 Generating tests for: $file"
          gh copilot suggest --type shell "Generate comprehensive unit tests for the code in $file"
        }
        
        # Parse arguments
        COMMAND=""
        MODEL=""
        FILE=""
        INTERACTIVE=false
        OUTPUT=""
        
        while [[ $# -gt 0 ]]; do
          case $1 in
            setup|generate|explain|refactor|test|document|review|optimize)
              COMMAND="$1"
              shift
              ;;
            --model)
              MODEL="$2"
              shift 2
              ;;
            --file)
              FILE="$2"
              shift 2
              ;;
            --interactive)
              INTERACTIVE=true
              shift
              ;;
            --output)
              OUTPUT="$2"
              shift 2
              ;;
            -h|--help)
              show_usage
              exit 0
              ;;
            *)
              echo "Unknown option: $1"
              show_usage
              exit 1
              ;;
          esac
        done
        
        case "$COMMAND" in
          setup)
            setup_workflow
            ;;
          generate)
            if [[ "$INTERACTIVE" == "true" ]]; then
              echo "Enter code description:"
              read -r description
              generate_code "$description" "$OUTPUT"
            else
              echo "❌ Description required for generate command"
              exit 1
            fi
            ;;
          explain)
            if [[ -n "$FILE" ]]; then
              explain_code "$FILE"
            else
              echo "❌ File required for explain command"
              exit 1
            fi
            ;;
          test)
            if [[ -n "$FILE" ]]; then
              generate_tests "$FILE"
            else
              echo "❌ File required for test command"
              exit 1
            fi
            ;;
          "")
            echo "❌ No command specified"
            show_usage
            exit 1
            ;;
          *)
            echo "❌ Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
        esac
      '';
    };
    
    # AI development shortcuts
    home-manager.users.yuki.home.shellAliases = {
      # AI workflow shortcuts
      "ai-setup" = "ai-workflow setup";
      "ai-gen" = "ai-workflow generate --interactive";
      "ai-explain" = "ai-workflow explain";
      "ai-test" = "ai-workflow test";
      "ai-doc" = "ai-workflow document";
      
      # Quick AI commands
      "ask-ai" = "gh copilot suggest";
      "explain-this" = "gh copilot explain";
      
      # Health checks
      "ai-status" = "ai-health && copilot-health";
    };
    
    # Combined AI health check
    home-manager.users.yuki.home.file."bin/ai-tools-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🤖 AI Development Tools Health Check"
        echo "==================================="
        
        # Run individual health checks
        if command -v copilot-health &> /dev/null; then
          copilot-health
          echo ""
        fi
        
        if command -v ai-health &> /dev/null; then
          ai-health
          echo ""
        fi
        
        # Overall status
        echo "📊 Overall AI Status:"
        echo "Profile: ${config.web.ai.profile}"
        echo "Privacy mode: ${config.web.ai.privacy.dataRetention}"
        echo "Caching: ${if config.web.ai.performance.enableCaching then "enabled" else "disabled"}"
        
        echo ""
        echo "✅ AI tools health check completed!"
      '';
    };
  };
}