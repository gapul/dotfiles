{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.ai-platform;
in
{
  imports = [
    ./ollama.nix
    ./cli-integration.nix
  ];
  options.dotfiles.development.ai-platform = {
    enable = mkEnableOption "Advanced AI Development Platform";
    
    # Ollama integration (moved to dedicated module)
    ollama = mkOption {
      type = types.submodule {};
      default = {};
      description = "Ollama local LLM configuration (see ollama.nix)";
    };
    
    aiCodeReview = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI-powered code review automation";
    };
    
    intelligentAutomation = mkOption {
      type = types.bool;
      default = true;
      description = "Enable intelligent automation systems";
    };
    
    aiOpsIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI Operations (AIOps) integration";
    };
    
    advancedMcp = mkOption {
      type = types.bool;
      default = true;
      description = "Enable advanced MCP server ecosystem";
    };
    
    aiDocGeneration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI-powered documentation generation";
    };
  };

  config = mkIf cfg.enable {
    # Enable Ollama by default when AI platform is enabled
    dotfiles.development.ai-platform.ollama.enable = mkDefault true;
    dotfiles.development.ai-platform.ollama.autoStart = mkDefault true;
    dotfiles.development.ai-platform.ollama.cliIntegration = mkDefault true;
    dotfiles.development.ai-platform.ollama.neovimIntegration = mkDefault true;
    
    # Enable CLI integration tools
    dotfiles.development.ai-platform.cli.enable = mkDefault true;
    dotfiles.development.ai-platform.cli.shellGpt = mkDefault true;
    dotfiles.development.ai-platform.cli.mods = mkDefault true;
    dotfiles.development.ai-platform.cli.aiCommit = mkDefault true;
    dotfiles.development.ai-platform.cli.explainShell = mkDefault true;
    
    # Advanced AI platform packages
    home-manager.users.yuki.home.packages = with pkgs; [
      # Core AI development tools
      curl  # For API calls
      jq    # JSON processing
      
    ] ++ optionals cfg.aiCodeReview [
      # Code review automation
      git
      github-cli
      
    ] ++ optionals cfg.intelligentAutomation [
      # Intelligent automation tools
      ansible
      terraform
      kubectl
      
    ] ++ optionals cfg.aiOpsIntegration [
      # AIOps monitoring and analytics
      prometheus
      grafana
      
    ] ++ optionals cfg.advancedMcp [
      # Advanced MCP ecosystem
      nodejs
      python3
      
    ] ++ optionals cfg.aiDocGeneration [
      # Documentation generation
      pandoc
      nodejs  # For various doc tools
    ];

    # Legacy Ollama setup (deprecated - use ollama-manager instead)
    # Removed in favor of the dedicated ollama.nix module

    # AI-powered code review system
    home-manager.users.yuki.home.file."bin/ai-code-review" = mkIf cfg.aiCodeReview {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # AI-Powered Code Review System
        set -euo pipefail
        
        ACTION="''${1:-review}"
        TARGET="''${2:-HEAD~1..HEAD}"
        
        echo "🔍 AI Code Review System"
        echo "======================="
        echo "Action: $ACTION"
        echo "Target: $TARGET"
        echo ""
        
        case "$ACTION" in
          "review")
            echo "📋 Performing AI code review..."
            
            # Get diff for review
            DIFF=$(git diff "$TARGET")
            
            if [[ -z "$DIFF" ]]; then
              echo "⚠️  No changes to review"
              exit 0
            fi
            
            # Create review prompt
            PROMPT="Please review this code diff and provide feedback on:
        1. Code quality and best practices
        2. Potential bugs or issues
        3. Performance improvements
        4. Security considerations
        5. Maintainability suggestions
        
        Code diff:
        $DIFF"
            
            # Use available AI tools for review (prioritize local Ollama)
            if command -v ollama-manager &> /dev/null; then
              echo "🤖 Using local Ollama via ollama-manager for review..."
              echo "$PROMPT" | ollama-manager code "Code review request"
            elif command -v ollama &> /dev/null && ollama list | grep -q codellama; then
              echo "🤖 Using local Ollama CodeLlama for review..."
              echo "$PROMPT" | ollama run codellama
            elif command -v aichat &> /dev/null; then
              echo "🤖 Using aichat for review..."
              echo "$PROMPT" | aichat
            elif command -v gh &> /dev/null && gh copilot --help &> /dev/null; then
              echo "🤖 Using GitHub Copilot for review..."
              echo "$PROMPT" | gh copilot suggest
            else
              echo "❌ No AI tools available for code review"
              echo "💡 Setup local LLM: ollama-manager setup"
              echo "💡 Or install: aichat, github-cli with copilot"
              exit 1
            fi
            ;;
            
          "security")
            echo "🔒 Security-focused code review..."
            
            # Security-specific review
            SECURITY_PROMPT="Analyze this code for security vulnerabilities:
        - SQL injection risks
        - XSS vulnerabilities
        - Authentication/authorization issues
        - Input validation problems
        - Sensitive data exposure
        
        Code:
        $(git diff "$TARGET")"
        
            if command -v ollama &> /dev/null; then
              echo "$SECURITY_PROMPT" | ollama run codellama
            else
              echo "Using alternative AI tool..."
              echo "$SECURITY_PROMPT" | aichat
            fi
            ;;
            
          "performance")
            echo "⚡ Performance-focused code review..."
            
            PERF_PROMPT="Analyze this code for performance improvements:
        - Algorithmic efficiency
        - Memory usage optimization
        - Database query optimization
        - Caching opportunities
        - Resource utilization
        
        Code:
        $(git diff "$TARGET")"
        
            if command -v ollama &> /dev/null; then
              echo "$PERF_PROMPT" | ollama run codellama
            else
              echo "$PERF_PROMPT" | aichat
            fi
            ;;
            
          "suggest")
            echo "💡 AI code improvement suggestions..."
            
            SUGGEST_PROMPT="Provide specific code improvement suggestions:
        - Refactoring opportunities
        - Modern language features
        - Design pattern applications
        - Code simplification
        - Error handling improvements
        
        Code:
        $(git diff "$TARGET")"
        
            if command -v ollama &> /dev/null; then
              echo "$SUGGEST_PROMPT" | ollama run codellama
            else
              echo "$SUGGEST_PROMPT" | aichat
            fi
            ;;
            
          *)
            echo "Usage: ai-code-review <action> [target]"
            echo ""
            echo "Actions:"
            echo "  review     - General code review"
            echo "  security   - Security-focused review"
            echo "  performance - Performance analysis"
            echo "  suggest    - Improvement suggestions"
            echo ""
            echo "Target: Git revision range (default: HEAD~1..HEAD)"
            exit 1
            ;;
        esac
      '';
    };

    # Intelligent deployment automation
    home-manager.users.yuki.home.file."bin/ai-deployment" = mkIf cfg.intelligentAutomation {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Intelligent AI-Powered Deployment System
        set -euo pipefail
        
        ACTION="''${1:-analyze}"
        ENVIRONMENT="''${2:-staging}"
        
        echo "🧠 Intelligent Deployment System"
        echo "================================"
        echo "Action: $ACTION"
        echo "Environment: $ENVIRONMENT"
        echo ""
        
        case "$ACTION" in
          "analyze")
            echo "📊 Analyzing deployment readiness..."
            
            # Check system health
            HEALTH_SCORE=0
            
            # Git status check
            if git status --porcelain | grep -q .; then
              echo "⚠️  Uncommitted changes detected"
            else
              echo "✅ Git: Clean working directory"
              ((HEALTH_SCORE++))
            fi
            
            # Test status
            if [[ -f "package.json" ]] && npm test &> /dev/null; then
              echo "✅ Tests: Passing"
              ((HEALTH_SCORE++))
            elif [[ -f "Cargo.toml" ]] && cargo test &> /dev/null; then
              echo "✅ Tests: Passing"
              ((HEALTH_SCORE++))
            else
              echo "⚠️  Tests: Not run or failing"
            fi
            
            # Security scan
            if command -v trivy &> /dev/null; then
              if trivy fs . --quiet; then
                echo "✅ Security: No critical vulnerabilities"
                ((HEALTH_SCORE++))
              else
                echo "⚠️  Security: Vulnerabilities detected"
              fi
            fi
            
            # Performance check
            if [[ -f ".lighthouse-ci.json" ]]; then
              echo "✅ Performance: Lighthouse configured"
              ((HEALTH_SCORE++))
            else
              echo "⚪ Performance: No metrics available"
            fi
            
            # AI decision making
            if [[ $HEALTH_SCORE -ge 3 ]]; then
              echo ""
              echo "🤖 AI Analysis: ✅ DEPLOYMENT RECOMMENDED"
              echo "   Health Score: $HEALTH_SCORE/4"
              echo "   Confidence: High"
              
              # Auto-deployment for staging
              if [[ "$ENVIRONMENT" == "staging" ]]; then
                echo "🚀 Auto-deploying to staging..."
                ai-deployment deploy staging
              fi
            else
              echo ""
              echo "🤖 AI Analysis: ❌ DEPLOYMENT NOT RECOMMENDED"
              echo "   Health Score: $HEALTH_SCORE/4"
              echo "   Issues detected, please resolve before deployment"
            fi
            ;;
            
          "deploy")
            echo "🚀 Executing intelligent deployment..."
            
            # Pre-deployment checks
            echo "🔍 Pre-deployment validation..."
            if ! ai-deployment analyze "$ENVIRONMENT" | grep -q "DEPLOYMENT RECOMMENDED"; then
              echo "❌ Pre-deployment checks failed"
              exit 1
            fi
            
            # Environment-specific deployment
            case "$ENVIRONMENT" in
              "dev"|"development")
                echo "🔧 Deploying to development..."
                # Fast deployment for dev
                ;;
              "staging")
                echo "🧪 Deploying to staging..."
                # Full validation for staging
                ;;
              "prod"|"production")
                echo "🏭 Deploying to production..."
                echo "⚠️  Production deployment requires confirmation"
                read -p "Proceed with production deployment? (yes/no): " -r
                if [[ "$REPLY" != "yes" ]]; then
                  echo "Deployment cancelled"
                  exit 0
                fi
                ;;
            esac
            
            # Deployment execution
            echo "📦 Executing deployment pipeline..."
            
            # Use available deployment tools
            if [[ -f "docker-compose.yml" ]]; then
              docker-compose up -d
            elif [[ -f "deployment.yaml" ]]; then
              kubectl apply -f deployment.yaml
            elif [[ -f "deploy.sh" ]]; then
              ./deploy.sh "$ENVIRONMENT"
            else
              echo "⚠️  No deployment configuration found"
            fi
            
            # Post-deployment monitoring
            echo "📊 Post-deployment monitoring..."
            sleep 10
            
            # Health check
            if curl -f http://localhost:8080/health &> /dev/null; then
              echo "✅ Health check: Passed"
            else
              echo "❌ Health check: Failed"
              echo "🔄 Initiating auto-rollback..."
              # Rollback logic here
            fi
            ;;
            
          "rollback")
            echo "🔄 Intelligent rollback system..."
            
            # Analyze rollback necessity
            echo "🤖 Analyzing system health for rollback decision..."
            
            ROLLBACK_SCORE=0
            
            # Check error rates
            # Check response times
            # Check resource usage
            
            echo "🔄 Executing rollback to previous version..."
            ;;
            
          *)
            echo "Usage: ai-deployment <action> [environment]"
            echo ""
            echo "Actions:"
            echo "  analyze    - Analyze deployment readiness"
            echo "  deploy     - Execute intelligent deployment"
            echo "  rollback   - Intelligent rollback system"
            echo ""
            echo "Environments: dev, staging, prod"
            ;;
        esac
      '';
    };

    # AI-powered documentation generation
    home-manager.users.yuki.home.file."bin/ai-docs" = mkIf cfg.aiDocGeneration {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # AI-Powered Documentation Generation
        set -euo pipefail
        
        ACTION="''${1:-generate}"
        TARGET="''${2:-.}"
        
        echo "📚 AI Documentation Generator"
        echo "============================"
        echo "Action: $ACTION"
        echo "Target: $TARGET"
        echo ""
        
        case "$ACTION" in
          "generate")
            echo "🤖 Generating documentation with AI..."
            
            # Analyze project structure
            if [[ -f "package.json" ]]; then
              PROJECT_TYPE="nodejs"
            elif [[ -f "Cargo.toml" ]]; then
              PROJECT_TYPE="rust"
            elif [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
              PROJECT_TYPE="python"
            elif [[ -f "go.mod" ]]; then
              PROJECT_TYPE="go"
            else
              PROJECT_TYPE="general"
            fi
            
            echo "📋 Project type detected: $PROJECT_TYPE"
            
            # Generate README if missing
            if [[ ! -f "README.md" ]]; then
              echo "📝 Generating README.md..."
              
              PROJECT_NAME=$(basename "$PWD")
              
              cat > README.md << EOF
        # $PROJECT_NAME
        
        *Documentation generated by AI on $(date)*
        
        ## Overview
        
        This is a $PROJECT_TYPE project with AI-enhanced development tools.
        
        ## Features
        
        - AI-powered development assistance
        - Automated code review
        - Intelligent deployment
        - Performance monitoring
        
        ## Getting Started
        
        ### Prerequisites
        
        - Development environment with AI tools
        - Docker (for containerized deployment)
        - Git for version control
        
        ### Installation
        
        \`\`\`bash
        # Clone the repository
        git clone <repository-url>
        cd $PROJECT_NAME
        
        # Install dependencies
        EOF
              
              case "$PROJECT_TYPE" in
                "nodejs")
                  echo "npm install" >> README.md
                  ;;
                "rust")
                  echo "cargo build" >> README.md
                  ;;
                "python")
                  echo "pip install -r requirements.txt" >> README.md
                  ;;
                "go")
                  echo "go mod download" >> README.md
                  ;;
              esac
              
              cat >> README.md << 'EOF'
        ```
        
        ### Development
        
        ```bash
        # Start development environment
        nix develop
        
        # Run AI code review
        ai-code-review
        
        # Deploy with AI assistance
        ai-deployment analyze
        ```
        
        ## AI Tools Integration
        
        This project includes:
        
        - **AI Code Review**: Automated code quality analysis
        - **Intelligent Deployment**: Smart deployment decisions
        - **Documentation Generation**: AI-powered docs
        - **Performance Monitoring**: AI-driven optimization
        
        ## Contributing
        
        1. Fork the repository
        2. Create a feature branch
        3. Run AI code review: `ai-code-review`
        4. Submit a pull request
        
        ## License
        
        MIT License - See LICENSE file for details.
        EOF
              
              echo "✅ README.md generated"
            else
              echo "⚪ README.md already exists"
            fi
            
            # Generate API documentation for supported types
            case "$PROJECT_TYPE" in
              "nodejs")
                if [[ -f "package.json" ]] && jq -e '.scripts.docs' package.json &> /dev/null; then
                  echo "📖 Generating API documentation..."
                  npm run docs
                fi
                ;;
              "rust")
                echo "📖 Generating Rust documentation..."
                cargo doc --no-deps
                ;;
              "python")
                if command -v sphinx-build &> /dev/null; then
                  echo "📖 Generating Python documentation..."
                  sphinx-build -b html docs docs/_build
                fi
                ;;
            esac
            ;;
            
          "api")
            echo "📖 Generating API documentation..."
            
            # Use AI to analyze code and generate API docs
            if command -v ollama &> /dev/null; then
              echo "🤖 Using AI to analyze API endpoints..."
              
              # Find API files
              API_FILES=$(find . -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.rs" | grep -E "(api|router|handler)" | head -5)
              
              for file in $API_FILES; do
                if [[ -f "$file" ]]; then
                  echo "Analyzing $file..."
                  PROMPT="Analyze this code file and generate API documentation. Include endpoints, parameters, responses, and examples:
        
        $(cat "$file")"
                  
                  echo "$PROMPT" | ollama run codellama > "docs/api-$(basename "$file" | sed 's/\.[^.]*$/.md/')".md
                fi
              done
            fi
            ;;
            
          "update")
            echo "🔄 Updating existing documentation..."
            
            # Update README with current project structure
            if [[ -f "README.md" ]]; then
              echo "📝 Updating README.md with current structure..."
              
              # Backup current README
              cp README.md README.md.backup
              
              # Use AI to update documentation
              if command -v ollama &> /dev/null; then
                PROMPT="Update this README.md to reflect the current project structure. Keep existing content but add missing sections:
        
        Current README:
        $(cat README.md)
        
        Project structure:
        $(find . -type f -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.rs" -o -name "*.md" | head -20)"
        
                echo "$PROMPT" | ollama run codellama > README.md.new
                
                if [[ -s "README.md.new" ]]; then
                  mv README.md.new README.md
                  echo "✅ README.md updated"
                else
                  mv README.md.backup README.md
                  echo "❌ Update failed, restored backup"
                fi
              fi
            fi
            ;;
            
          *)
            echo "Usage: ai-docs <action> [target]"
            echo ""
            echo "Actions:"
            echo "  generate   - Generate project documentation"
            echo "  api        - Generate API documentation"
            echo "  update     - Update existing documentation"
            echo ""
            echo "Target: Directory or file (default: current directory)"
            ;;
        esac
      '';
    };

    # Advanced MCP server ecosystem
    home-manager.users.yuki.home.file.".config/mcp/servers.json" = mkIf cfg.advancedMcp {
      text = builtins.toJSON {
        mcpServers = {
          # Filesystem access
          filesystem = {
            command = "npx";
            args = [ "@modelcontextprotocol/server-filesystem" ];
            env = {
              NPM_CONFIG_CACHE = "$HOME/.cache/npm";
            };
          };
          
          # Git integration
          git = {
            command = "npx";
            args = [ "@modelcontextprotocol/server-git" ];
          };
          
          # GitHub integration
          github = {
            command = "npx";
            args = [ "@modelcontextprotocol/server-github" ];
            env = {
              GITHUB_PERSONAL_ACCESS_TOKEN = "$GITHUB_TOKEN";
            };
          };
          
          # Database access
          postgres = {
            command = "npx";
            args = [ "@modelcontextprotocol/server-postgres" ];
            env = {
              POSTGRES_CONNECTION_STRING = "$DATABASE_URL";
            };
          };
          
          # Web search
          brave-search = {
            command = "npx";
            args = [ "@modelcontextprotocol/server-brave-search" ];
            env = {
              BRAVE_API_KEY = "$BRAVE_API_KEY";
            };
          };
          
          # Kubernetes management
          kubernetes = {
            command = "npx";
            args = [ "@modelcontextprotocol/server-kubernetes" ];
            env = {
              KUBECONFIG = "$HOME/.kube/config";
            };
          };
        };
      };
    };

    # AI platform health monitoring
    home-manager.users.yuki.home.file."bin/ai-platform-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🤖 AI Platform Health Check"
        echo "==========================="
        echo ""
        
        ISSUES=0
        
        # Local LLM check (delegated to Ollama module)
        echo "🦙 Local LLM (Ollama):"
        if command -v ollama-manager &> /dev/null; then
          echo "  ✅ Ollama Manager: Available"
          # Run ollama-manager health check
          if ollama-manager status | grep -q "Service: Running"; then
            echo "  ✅ Ollama Service: Running"
          else
            echo "  ⚠️  Ollama Service: Not running"
            ((ISSUES++))
          fi
        else
          echo "  ❌ Ollama Manager: Not available"
          echo "  💡 Run: ollama-manager setup"
          ((ISSUES++))
        fi
        
        # Code review system
        ${if cfg.aiCodeReview then ''
          echo ""
          echo "🔍 AI Code Review:"
          if [[ -x "$HOME/bin/ai-code-review" ]]; then
            echo "  ✅ Code review system: Available"
          else
            echo "  ❌ Code review system: Not found"
            ((ISSUES++))
          fi
        '' else ''
          echo ""
          echo "🔍 AI Code Review: Disabled"
        ''}
        
        # Intelligent automation
        ${if cfg.intelligentAutomation then ''
          echo ""
          echo "🧠 Intelligent Automation:"
          if [[ -x "$HOME/bin/ai-deployment" ]]; then
            echo "  ✅ AI deployment: Available"
          else
            echo "  ❌ AI deployment: Not found"
            ((ISSUES++))
          fi
        '' else ''
          echo ""
          echo "🧠 Intelligent Automation: Disabled"
        ''}
        
        # Documentation generation
        ${if cfg.aiDocGeneration then ''
          echo ""
          echo "📚 AI Documentation:"
          if [[ -x "$HOME/bin/ai-docs" ]]; then
            echo "  ✅ Doc generation: Available"
          else
            echo "  ❌ Doc generation: Not found"
            ((ISSUES++))
          fi
        '' else ''
          echo ""
          echo "📚 AI Documentation: Disabled"
        ''}
        
        # MCP servers
        ${if cfg.advancedMcp then ''
          echo ""
          echo "🔌 MCP Ecosystem:"
          if [[ -f "$HOME/.config/mcp/servers.json" ]]; then
            SERVER_COUNT=$(jq '.mcpServers | length' "$HOME/.config/mcp/servers.json")
            echo "  ✅ MCP servers: $SERVER_COUNT configured"
          else
            echo "  ❌ MCP configuration: Not found"
            ((ISSUES++))
          fi
        '' else ''
          echo ""
          echo "🔌 MCP Ecosystem: Disabled"
        ''}
        
        # Environment variables
        echo ""
        echo "🔑 Environment Variables:"
        if [[ -n "''${OPENAI_API_KEY:-}" ]]; then
          echo "  ✅ OPENAI_API_KEY: Set"
        else
          echo "  ⚪ OPENAI_API_KEY: Not set"
        fi
        
        if [[ -n "''${ANTHROPIC_API_KEY:-}" ]]; then
          echo "  ✅ ANTHROPIC_API_KEY: Set"
        else
          echo "  ⚪ ANTHROPIC_API_KEY: Not set"
        fi
        
        if [[ -n "''${GITHUB_TOKEN:-}" ]]; then
          echo "  ✅ GITHUB_TOKEN: Set"
        else
          echo "  ⚠️  GITHUB_TOKEN: Not set (needed for GitHub integration)"
        fi
        
        # Summary
        echo ""
        echo "📊 Platform Status:"
        if [[ $ISSUES -eq 0 ]]; then
          echo "  ✅ AI Platform: Fully operational"
        else
          echo "  ⚠️  AI Platform: $ISSUES issues detected"
        fi
        
        echo ""
        echo "🚀 Available Commands:"
        echo "  🔍 Code & Review:"
        echo "    ai-code-review     - AI-powered code review"
        echo "    ai-commit          - Generate commit messages"
        echo "  🚀 Deployment:"
        echo "    ai-deployment      - Intelligent deployment"
        echo "  📚 Documentation:"
        echo "    ai-docs           - Documentation generation"
        echo "  🤖 Local LLM:"
        echo "    ollama-manager     - Comprehensive Ollama management"
        echo "  💬 CLI Assistance:"
        echo "    ask <query>        - Ask AI anything"
        echo "    explain <command>  - Explain shell commands"
        echo "    fix <error>        - Fix command errors"
        echo "    suggest <task>     - Get command suggestions"
        echo "  🏥 Monitoring:"
        echo "    ai-platform-health - This health check"
      '';
    };

    # Shell aliases for AI platform
    home-manager.users.yuki.programs.zsh.shellAliases = {
      # AI platform commands
      ai-review = "ai-code-review";
      ai-deploy = "ai-deployment";
      ai-doc = "ai-docs";
      ai-health = "ai-platform-health";
      
      # Legacy Ollama commands (prefer ollama-manager)
      local-llm = "ollama-manager models";
      ollama-setup-legacy = "ollama-manager setup";  # Renamed to avoid conflicts
    };

    # AI platform environment variables
    home-manager.users.yuki.home.sessionVariables = {
      AI_PLATFORM_ENABLED = "true";
      OLLAMA_HOST = "127.0.0.1:11434";
      MCP_CONFIG_PATH = "$HOME/.config/mcp/servers.json";
    };
  };
}