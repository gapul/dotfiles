# Web開発環境 - メイン統合モジュール
# Web開発環境全体の設定と管理

{ lib, pkgs, config, ... }:

with lib;

{
  imports = [
    ./core
    ./tooling
    ./deployment.nix
    ./performance-monitoring.nix
  ];

  options.web = {
    enable = mkEnableOption "Web development environment";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" "performance" ];
      default = "standard";
      description = "Web development environment profile";
    };
    
    features = {
      core = mkOption {
        type = types.bool;
        default = true;
        description = "Enable core web development tools";
      };
      
      tooling = mkOption {
        type = types.bool;
        default = true;
        description = "Enable additional development tools";
      };
      
      
      deployment = mkOption {
        type = types.bool;
        default = true;
        description = "Enable deployment automation";
      };
      
      performanceMonitoring = mkOption {
        type = types.bool;
        default = true;
        description = "Enable performance monitoring and analysis";
      };
    };
    
    autoSetup = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically configure optimal settings";
    };
  };

  config = mkIf config.web.enable {
    # Enable components based on features and profile
    web.core.enable = mkDefault config.web.features.core;
    web.tooling.enable = mkDefault config.web.features.tooling;
    
    # Enable deployment features
    dotfiles.development.web.deployment.enable = mkDefault config.web.features.deployment;
    dotfiles.development.web.performance-monitoring.enable = mkDefault config.web.features.performanceMonitoring;
    
    # Profile-specific configurations
    web.core.profile = mkDefault config.web.profile;
    dotfiles.development.web.deployment.profile = mkDefault config.web.profile;
    dotfiles.development.web.performance-monitoring.profile = mkDefault config.web.profile;
    
    
    # Global web development packages
    home-manager.users.yuki.home.packages = with pkgs; [
      # Modern CLI tools
      tree-sitter
      ripgrep
      fd
      fzf
      jq
      yq-go
      
      # Git utilities
      git
      git-lfs
      gitui
      lazygit
      
      # Network tools
      curl
      wget
      httpie
      
      # File management
      tree
      eza
      bat
      
      # Performance monitoring
      htop
      btop
      hyperfine
    ];
    
    # Global environment variables
    home-manager.users.yuki.home.sessionVariables = {
      # Web development preferences
      WEB_PROFILE = config.web.profile;
      WEB_PRIMARY_FRAMEWORK = "react";
      
      # Node.js optimizations
      NODE_OPTIONS = "--max-old-space-size=4096";
      
      # Development preferences
      # Note: EDITOR managed in main flake.nix
      BROWSER = "default";
    };
    
    # Global shell aliases
    home-manager.users.yuki.home.shellAliases = {
      # Template-based project commands
      "web-init" = "web-create";
      "web-new" = "web-create";
      "web-create-project" = "web-create";
      
      # Environment management
      "web-health" = "web-env-health";
      "web-status" = "web-env-health";
      "web-check" = "web-env-health";
      
      # Common shortcuts
      "dev" = "npm run dev";
      "build" = "npm run build";
      "test" = "npm test";
      "lint" = "npm run lint";
    };
    
    # Web development workflow script
    home-manager.users.yuki.home.file."bin/web-workflow" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        show_usage() {
          cat << EOF
        Usage: web-workflow <command> [options]
        
        COMMANDS:
          init        Initialize new web project
          dev         Start development server
          build       Build for production
          test        Run tests
          lint        Lint code
          deploy      Deploy application
          health      Check environment health
          
        OPTIONS:
          --framework FRAMEWORK  Framework (react, vue, svelte, astro)
          --typescript          Enable TypeScript
          --desktop             Enable desktop app (Tauri)
          --dir DIR             Target directory
          
        EXAMPLES:
          web-workflow init my-app --framework react --typescript
          web-workflow dev
          web-workflow build --desktop
          web-workflow deploy --framework nextjs
        EOF
        }
        
        init_project() {
          local name="$1"
          local framework="''${2:-react}"
          local use_typescript="''${3:-true}"
          local use_desktop="''${4:-false}"
          local target_dir="''${5:-.}"
          
          echo "🚀 Initializing web project: $name"
          echo "Framework: $framework"
          echo "TypeScript: $use_typescript"
          echo "Desktop: $use_desktop"
          echo "Directory: $target_dir"
          echo ""
          
          case "$framework" in
            react)
              if [[ "$use_desktop" == "true" ]]; then
                tauri-init "$name" react
              else
                react-init "$name" vite --dir "$target_dir"
              fi
              ;;
            nextjs)
              nextjs-init "$name" --dir "$target_dir"
              ;;
            vue)
              echo "Vue support coming soon"
              exit 1
              ;;
            svelte)
              echo "Svelte support coming soon"
              exit 1
              ;;
            astro)
              echo "Astro support coming soon"
              exit 1
              ;;
            *)
              echo "❌ Unknown framework: $framework"
              exit 1
              ;;
          esac
          
          echo "✅ Project initialized successfully!"
        }
        
        dev_server() {
          echo "🔄 Starting development server..."
          
          # Check if it's a Tauri project
          if [[ -f "src-tauri/Cargo.toml" ]]; then
            tauri-dev
          # Check if it's a Next.js project
          elif [[ -f "next.config.js" ]] || [[ -f "next.config.mjs" ]]; then
            next-dev
          # Default to npm/package.json
          elif [[ -f "package.json" ]]; then
            npm run dev
          else
            echo "❌ No recognized project in current directory"
            exit 1
          fi
        }
        
        build_app() {
          local use_desktop="''${1:-false}"
          
          echo "🏗️  Building application..."
          
          if [[ "$use_desktop" == "true" ]] && [[ -f "src-tauri/Cargo.toml" ]]; then
            tauri-build
          elif [[ -f "next.config.js" ]] || [[ -f "next.config.mjs" ]]; then
            next-build
          elif [[ -f "package.json" ]]; then
            npm run build
          else
            echo "❌ No recognized project in current directory"
            exit 1
          fi
        }
        
        test_app() {
          echo "🧪 Running tests..."
          
          if [[ -f "src-tauri/Cargo.toml" ]]; then
            # Tauri project - test both frontend and backend
            npm test
            cd src-tauri && cargo test && cd ..
          elif [[ -f "package.json" ]]; then
            npm test
          else
            echo "❌ No test configuration found"
            exit 1
          fi
        }
        
        lint_app() {
          echo "🔍 Linting code..."
          
          if [[ -f "package.json" ]]; then
            npm run lint
          else
            echo "❌ No lint configuration found"
            exit 1
          fi
        }
        
        deploy_app() {
          local framework="$1"
          
          echo "🚀 Deploying application..."
          
          case "$framework" in
            nextjs)
              echo "Deploying Next.js app (assumed Vercel)"
              npx vercel --prod
              ;;
            *)
              echo "🏗️  Building for deployment..."
              build_app
              echo "📦 Build completed. Manual deployment required."
              ;;
          esac
        }
        
        health_check() {
          echo "🏥 Web Development Environment Health Check"
          echo "=========================================="
          
          web-env-health
        }
        
        # Parse arguments
        COMMAND=""
        FRAMEWORK="react"
        USE_TYPESCRIPT="true"
        USE_DESKTOP="false"
        TARGET_DIR="."
        
        while [[ $# -gt 0 ]]; do
          case $1 in
            init|dev|build|test|lint|deploy|health)
              COMMAND="$1"
              shift
              ;;
            --framework)
              FRAMEWORK="$2"
              shift 2
              ;;
            --typescript)
              USE_TYPESCRIPT="true"
              shift
              ;;
            --desktop)
              USE_DESKTOP="true"
              shift
              ;;
            --dir)
              TARGET_DIR="$2"
              shift 2
              ;;
            -h|--help)
              show_usage
              exit 0
              ;;
            *)
              if [[ -z "$COMMAND" ]]; then
                echo "Unknown command: $1"
                show_usage
                exit 1
              else
                # Pass remaining args to command
                break
              fi
              ;;
          esac
        done
        
        case "$COMMAND" in
          init)
            if [[ $# -lt 1 ]]; then
              echo "❌ Project name required"
              exit 1
            fi
            init_project "$1" "$FRAMEWORK" "$USE_TYPESCRIPT" "$USE_DESKTOP" "$TARGET_DIR"
            ;;
          dev)
            dev_server
            ;;
          build)
            build_app "$USE_DESKTOP"
            ;;
          test)
            test_app
            ;;
          lint)
            lint_app
            ;;
          deploy)
            deploy_app "$FRAMEWORK"
            ;;
          health)
            health_check
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
    
    # Comprehensive health check
    home-manager.users.yuki.home.file."bin/web-env-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🌐 Web Development Environment Health Check"
        echo "=========================================="
        
        # Core environment check
        if command -v web-health &> /dev/null; then
          web-health
          echo ""
        fi
        
        # Template system check
        if command -v template-manager.sh &> /dev/null; then
          echo "📦 Template System:"
          template-manager.sh health
          echo ""
        fi
        
        # Overall configuration
        echo "📊 Overall Configuration:"
        echo "Profile: ${config.web.profile}"
        echo "Template-based development: ✅"
        echo "Features enabled:"
        echo "  Core: ${if config.web.features.core then "✅" else "❌"}"
        echo "  Tooling: ${if config.web.features.tooling then "✅" else "❌"}"
        echo ""
        echo "📋 Available commands:"
        echo "  web-create <name>     - Create new project"
        echo "  template-manager.sh   - Manage templates"
        echo "  perf-monitor          - Performance monitoring"
        echo "  deploy                - Deployment automation"
        echo "  rollback              - Deployment rollback"
        
        echo ""
        echo "✅ Web development environment health check completed!"
      '';
    };
  };
}