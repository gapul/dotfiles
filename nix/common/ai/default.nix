# AI Development Assistant Integration System
# Comprehensive AI-powered development tools and automation
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  imports = [
    ./assistants
    ./automation
    ./context-management
    ./workflows
    ./analysis
    ./context-aware
  ];

  options.dotfiles.ai = {
    enable = mkEnableOption "AI development assistant integration";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "comprehensive" "enterprise" ];
      default = "standard";
      description = "AI integration profile level";
    };
    
    codeAssistant = {
      enable = mkEnableOption "AI code assistant features";
      
      provider = mkOption {
        type = types.enum [ "github-copilot" "codeium" "tabnine" "local-model" ];
        default = "github-copilot";
        description = "Primary AI code assistant provider";
      };
      
      enhancedCompletion = mkOption {
        type = types.bool;
        default = true;
        description = "Enable enhanced code completion with context";
      };
      
      documentationGeneration = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic documentation generation";
      };
      
      codeReview = mkOption {
        type = types.bool;
        default = false;
        description = "Enable AI-powered code review";
      };
    };
    
    automation = {
      enable = mkEnableOption "AI automation features";
      
      commitMessageGeneration = mkOption {
        type = types.bool;
        default = true;
        description = "Generate intelligent commit messages";
      };
      
      testGeneration = mkOption {
        type = types.bool;
        default = true;
        description = "Automatic test case generation";
      };
      
      refactoringAssistance = mkOption {
        type = types.bool;
        default = false;
        description = "AI-powered refactoring suggestions";
      };
      
      bugDetection = mkOption {
        type = types.bool;
        default = true;
        description = "Intelligent bug detection and suggestions";
      };
    };
    
    contextManagement = {
      enable = mkEnableOption "AI context management";
      
      projectAnalysis = mkOption {
        type = types.bool;
        default = true;
        description = "Analyze project structure for better AI context";
      };
      
      codebaseIndexing = mkOption {
        type = types.bool;
        default = true;
        description = "Index codebase for intelligent assistance";
      };
      
      dependencyTracking = mkOption {
        type = types.bool;
        default = true;
        description = "Track dependencies for better suggestions";
      };
    };
    
    privacy = {
      localProcessing = mkOption {
        type = types.bool;
        default = false;
        description = "Prefer local AI processing when possible";
      };
      
      dataRetention = mkOption {
        type = types.enum [ "none" "session" "project" "persistent" ];
        default = "session";
        description = "AI data retention policy";
      };
      
      encryptedStorage = mkOption {
        type = types.bool;
        default = true;
        description = "Encrypt AI-related data storage";
      };
    };
    
    performance = {
      cacheResponses = mkOption {
        type = types.bool;
        default = true;
        description = "Cache AI responses for better performance";
      };
      
      batchRequests = mkOption {
        type = types.bool;
        default = true;
        description = "Batch AI requests for efficiency";
      };
      
      offlineMode = mkOption {
        type = types.bool;
        default = false;
        description = "Enable offline AI capabilities";
      };
    };
  };

  config = mkIf config.dotfiles.ai.enable {
    # Enable components based on profile
    dotfiles.ai = {
      codeAssistant.enable = mkDefault true;
      automation.enable = mkDefault (
        elem config.dotfiles.ai.profile [ "standard" "comprehensive" "enterprise" ]
      );
      contextManagement.enable = mkDefault (
        elem config.dotfiles.ai.profile [ "comprehensive" "enterprise" ]
      );
      workflows.enable = mkDefault (
        elem config.dotfiles.ai.profile [ "comprehensive" "enterprise" ]
      );
      analysis.enable = mkDefault (
        elem config.dotfiles.ai.profile [ "comprehensive" "enterprise" ]
      );
      contextAware.enable = mkDefault (
        elem config.dotfiles.ai.profile [ "comprehensive" "enterprise" ]
      );
    };

    # Core AI development tools
    environment.systemPackages = with pkgs; [
      # AI assistant tools
      (writeShellScriptBin "ai-assist" ''
        #!/bin/bash
        
        # Main AI assistant command interface
        
        set -euo pipefail
        
        COMMAND="''${1:-help}"
        shift || true
        
        case "$COMMAND" in
          help)
            echo "🤖 AI Development Assistant"
            echo "=========================="
            echo ""
            echo "Available commands:"
            echo "  ai-assist code-complete <file>     - Get code completion suggestions"
            echo "  ai-assist doc-generate <file>      - Generate documentation"
            echo "  ai-assist commit-msg               - Generate commit message"
            echo "  ai-assist test-generate <file>     - Generate test cases"
            echo "  ai-assist review <file>            - Review code for improvements"
            echo "  ai-assist refactor <file>          - Suggest refactoring"
            echo "  ai-assist explain <file> [line]    - Explain code functionality"
            echo "  ai-assist debug <file> [error]     - Debug assistance"
            echo "  ai-assist optimize <file>          - Performance optimization suggestions"
            echo "  ai-assist status                   - Show AI assistant status"
            echo ""
            echo "Workflow commands:"
            echo "  ai-pre-commit-review               - Run pre-commit AI review"
            echo "  ai-branch-create <type> [desc]     - Create intelligent branch"
            echo "  ai-pr-create [base]                - Create AI-enhanced PR"
            echo "  ai-cicd-optimize                   - Analyze CI/CD optimization"
            echo "  ai-project-maintain [command]      - Project maintenance tasks"
            echo ""
            echo "Analysis commands:"
            echo "  ai-analyze-code <file/dir> [type]  - Comprehensive code analysis"
            echo "  ai-optimize-code <file>            - Code optimization suggestions"
            echo "  ai-quality-dashboard [project]     - Generate quality dashboard"
            echo ""
            echo "Context-aware commands:"
            echo "  ai-detect-context [project] [fmt]  - Detect development context"
            echo "  ai-context-suggest <action> [file] - Context-aware suggestions"
            echo "  ai-adaptive-workflow [command]     - Adaptive workflow management"
            echo ""
            echo "Configuration:"
            echo "  Provider: ${config.dotfiles.ai.codeAssistant.provider}"
            echo "  Profile: ${config.dotfiles.ai.profile}"
            ;;
          
          status)
            echo "🤖 AI Assistant Status"
            echo "====================="
            echo "Profile: ${config.dotfiles.ai.profile}"
            echo "Provider: ${config.dotfiles.ai.codeAssistant.provider}"
            echo "Code completion: ${if config.dotfiles.ai.codeAssistant.enhancedCompletion then "enabled" else "disabled"}"
            echo "Documentation: ${if config.dotfiles.ai.codeAssistant.documentationGeneration then "enabled" else "disabled"}"
            echo "Automation: ${if config.dotfiles.ai.automation.enable then "enabled" else "disabled"}"
            echo "Context management: ${if config.dotfiles.ai.contextManagement.enable then "enabled" else "disabled"}"
            echo "Workflows: ${if config.dotfiles.ai.workflows.enable then "enabled" else "disabled"}"
            echo "Analysis: ${if config.dotfiles.ai.analysis.enable then "enabled" else "disabled"}"
            echo "Context-aware: ${if config.dotfiles.ai.contextAware.enable then "enabled" else "disabled"}"
            echo ""
            
            # Check provider availability
            case "${config.dotfiles.ai.codeAssistant.provider}" in
              github-copilot)
                if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
                  echo "✅ GitHub Copilot: Available"
                else
                  echo "❌ GitHub Copilot: Not authenticated"
                fi
                ;;
              codeium)
                echo "🔍 Codeium: Checking availability..."
                ;;
              *)
                echo "ℹ️  Provider configuration: ${config.dotfiles.ai.codeAssistant.provider}"
                ;;
            esac
            ;;
          
          code-complete)
            if [ $# -eq 0 ]; then
              echo "Usage: ai-assist code-complete <file>"
              exit 1
            fi
            ai-code-complete "$@"
            ;;
          
          doc-generate)
            if [ $# -eq 0 ]; then
              echo "Usage: ai-assist doc-generate <file>"
              exit 1
            fi
            ai-doc-generate "$@"
            ;;
          
          commit-msg)
            ai-commit-message
            ;;
          
          test-generate)
            if [ $# -eq 0 ]; then
              echo "Usage: ai-assist test-generate <file>"
              exit 1
            fi
            ai-test-generate "$@"
            ;;
          
          review)
            if [ $# -eq 0 ]; then
              echo "Usage: ai-assist review <file>"
              exit 1
            fi
            ai-code-review "$@"
            ;;
          
          refactor)
            if [ $# -eq 0 ]; then
              echo "Usage: ai-assist refactor <file>"
              exit 1
            fi
            ai-refactor-suggest "$@"
            ;;
          
          explain)
            if [ $# -eq 0 ]; then
              echo "Usage: ai-assist explain <file> [line]"
              exit 1
            fi
            ai-code-explain "$@"
            ;;
          
          debug)
            if [ $# -eq 0 ]; then
              echo "Usage: ai-assist debug <file> [error]"
              exit 1
            fi
            ai-debug-assist "$@"
            ;;
          
          optimize)
            if [ $# -eq 0 ]; then
              echo "Usage: ai-assist optimize <file>"
              exit 1
            fi
            ai-optimize-code "$@"
            ;;
          
          *)
            echo "Unknown command: $COMMAND"
            echo "Run 'ai-assist help' for available commands"
            exit 1
            ;;
        esac
      '')
      
      # Project context analyzer
      (writeShellScriptBin "ai-analyze-project" ''
        #!/bin/bash
        
        # Analyze project structure for AI context
        
        set -euo pipefail
        
        PROJECT_DIR="''${1:-$(pwd)}"
        OUTPUT_DIR="$HOME/.local/share/dotfiles-ai/context"
        
        mkdir -p "$OUTPUT_DIR"
        
        echo "🔍 Analyzing project structure: $PROJECT_DIR"
        
        ANALYSIS_FILE="$OUTPUT_DIR/project-analysis-$(date +%Y%m%d_%H%M%S).json"
        
        {
          echo "{"
          echo "  \"timestamp\": \"$(date -Iseconds)\","
          echo "  \"project_path\": \"$PROJECT_DIR\","
          echo "  \"analysis\": {"
          
          # Language detection
          echo "    \"languages\": ["
          find "$PROJECT_DIR" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.nix" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.cpp" -o -name "*.c" \) | \
            sed 's/.*\.//' | sort | uniq -c | sort -nr | \
            awk '{printf "      {\"language\": \"%s\", \"files\": %d},\n", $2, $1}' | sed '$ s/,$//'
          echo "    ],"
          
          # Project structure
          echo "    \"structure\": {"
          echo "      \"total_files\": $(find "$PROJECT_DIR" -type f | wc -l | tr -d ' '),"
          echo "      \"total_dirs\": $(find "$PROJECT_DIR" -type d | wc -l | tr -d ' '),"
          echo "      \"source_files\": $(find "$PROJECT_DIR" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.nix" -o -name "*.go" -o -name "*.rs" \) | wc -l | tr -d ' '),"
          
          # Configuration files
          echo "      \"config_files\": ["
          find "$PROJECT_DIR" -maxdepth 2 -type f \( -name "package.json" -o -name "Cargo.toml" -o -name "go.mod" -o -name "pyproject.toml" -o -name "flake.nix" -o -name "Makefile" -o -name "justfile" \) | \
            awk '{printf "        \"%s\",\n", $0}' | sed '$ s/,$//'
          echo "      ]"
          echo "    },"
          
          # Dependencies analysis
          echo "    \"dependencies\": {"
          if [ -f "$PROJECT_DIR/package.json" ]; then
            echo "      \"npm\": true,"
          fi
          if [ -f "$PROJECT_DIR/Cargo.toml" ]; then
            echo "      \"cargo\": true,"
          fi
          if [ -f "$PROJECT_DIR/go.mod" ]; then
            echo "      \"go_modules\": true,"
          fi
          if [ -f "$PROJECT_DIR/flake.nix" ]; then
            echo "      \"nix_flake\": true,"
          fi
          echo "      \"analyzed\": true"
          echo "    }"
          
          echo "  }"
          echo "}"
        } > "$ANALYSIS_FILE"
        
        echo "✅ Project analysis completed: $ANALYSIS_FILE"
        
        # Create symlink to latest analysis
        ln -sf "$ANALYSIS_FILE" "$OUTPUT_DIR/latest-analysis.json"
        
        # Display summary
        echo ""
        echo "📊 Project Summary:"
        jq -r '.analysis.languages[] | "  \(.language): \(.files) files"' "$ANALYSIS_FILE"
        echo "  Total files: $(jq -r '.analysis.structure.total_files' "$ANALYSIS_FILE")"
        echo "  Source files: $(jq -r '.analysis.structure.source_files' "$ANALYSIS_FILE")"
      '')
      
      # AI performance tracker
      (writeShellScriptBin "ai-performance-tracker" ''
        #!/bin/bash
        
        # Track AI assistant performance and usage
        
        set -euo pipefail
        
        METRICS_DIR="$HOME/.local/share/dotfiles-ai/metrics"
        mkdir -p "$METRICS_DIR"
        
        COMMAND="''${1:-status}"
        
        case "$COMMAND" in
          log)
            # Log AI operation
            OPERATION="$2"
            DURATION="$3"
            SUCCESS="''${4:-true}"
            
            echo "$(date -Iseconds),$OPERATION,$DURATION,$SUCCESS" >> "$METRICS_DIR/ai-usage.csv"
            ;;
          
          status)
            echo "🤖 AI Performance Metrics"
            echo "========================"
            
            if [ -f "$METRICS_DIR/ai-usage.csv" ]; then
              echo "Total operations: $(wc -l < "$METRICS_DIR/ai-usage.csv")"
              
              # Today's operations
              TODAY=$(date +%Y-%m-%d)
              TODAY_OPS=$(grep "^$TODAY" "$METRICS_DIR/ai-usage.csv" | wc -l)
              echo "Today's operations: $TODAY_OPS"
              
              # Success rate
              if [ "$TODAY_OPS" -gt 0 ]; then
                SUCCESS_COUNT=$(grep "^$TODAY" "$METRICS_DIR/ai-usage.csv" | grep ",true$" | wc -l)
                SUCCESS_RATE=$(( SUCCESS_COUNT * 100 / TODAY_OPS ))
                echo "Success rate: $SUCCESS_RATE%"
              fi
              
              # Most used operations
              echo ""
              echo "Most used operations:"
              awk -F',' '{print $2}' "$METRICS_DIR/ai-usage.csv" | sort | uniq -c | sort -nr | head -5 | \
                awk '{printf "  %s: %d times\n", $2, $1}'
            else
              echo "No usage data available yet"
            fi
            ;;
          
          clean)
            # Clean old metrics (keep last 30 days)
            CUTOFF_DATE=$(date -d '30 days ago' +%Y-%m-%d)
            if [ -f "$METRICS_DIR/ai-usage.csv" ]; then
              grep -v "^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "$METRICS_DIR/ai-usage.csv" > "$METRICS_DIR/ai-usage.tmp" || true
              awk -F',' -v cutoff="$CUTOFF_DATE" '$1 >= cutoff' "$METRICS_DIR/ai-usage.csv" >> "$METRICS_DIR/ai-usage.tmp" || true
              mv "$METRICS_DIR/ai-usage.tmp" "$METRICS_DIR/ai-usage.csv"
              echo "Cleaned old metrics (kept data from $CUTOFF_DATE onwards)"
            fi
            ;;
        esac
      '')
      
      # GitHub Copilot integration
      gh
      
      # JSON processing for AI data
      jq
      
      # Text processing utilities
      ripgrep
      fd
    ];

    # Create AI data directories
    system.activationScripts.aiDevelopmentAssistant = {
      text = ''
        # Create AI assistant data directories
        mkdir -p /var/lib/dotfiles-ai/{context,cache,models}
        chmod 755 /var/lib/dotfiles-ai
        
        # Create user-specific AI directories
        if [ -d "/Users/yuki" ]; then
          mkdir -p "/Users/yuki/.local/share/dotfiles-ai/{context,cache,metrics,config}"
          chown -R yuki:staff "/Users/yuki/.local/share/dotfiles-ai"
        fi
        
        echo "AI development assistant directories initialized"
      '';
    };
  };
}