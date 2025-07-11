# Web開発環境 - メイン統合モジュール
# Web開発環境全体の設定と管理

{ lib, pkgs, config, ... }:

with lib;

{
  imports = [
    ./core
    ./frameworks
    ./desktop
    ./tooling
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
      
      frameworks = mkOption {
        type = types.bool;
        default = true;
        description = "Enable web frameworks";
      };
      
      desktop = mkOption {
        type = types.bool;
        default = false;
        description = "Enable desktop app development (Tauri)";
      };
      
      tooling = mkOption {
        type = types.bool;
        default = true;
        description = "Enable additional development tools";
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
    web.frameworks.enable = mkDefault config.web.features.frameworks;
    web.desktop.enable = mkDefault config.web.features.desktop;
    web.tooling.enable = mkDefault config.web.features.tooling;
    
    # Profile-specific configurations
    web.core.profile = mkDefault config.web.profile;
    web.desktop.profile = mkDefault (
      if config.web.profile == "minimal" then "basic"
      else if config.web.profile == "standard" then "standard"
      else if config.web.profile == "full" then "advanced"
      else "production"
    );
    
    
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
      WEB_PRIMARY_FRAMEWORK = config.web.frameworks.primary;
      
      # Node.js optimizations
      NODE_OPTIONS = "--max-old-space-size=4096";
      
      # Development preferences
      EDITOR = "nvim";
      BROWSER = "default";
    };
    
    # Global shell aliases
    home-manager.users.yuki.home.shellAliases = {
      # Quick project commands
      "web-init" = "fw-init";
      "web-dev" = "dev-start";
      "web-build" = "build-app";
      "web-test" = "test-app";
      "web-lint" = "lint-app";
      
      # Environment management
      "web-health" = "web-env-health";
      "web-status" = "web-env-health";
      "web-check" = "web-env-health";
      
      # Common shortcuts
      "dev" = "npm run dev";
      "build" = "npm run build";
      "test" = "npm test";
      "lint" = "npm run lint";
      "install" = "pm install";
      "add" = "pm add";
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
          local framework="''${2:-${config.web.frameworks.primary}}"
          local use_typescript="''${3:-${toString config.web.frameworks.typescript}}"
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
        FRAMEWORK="${config.web.frameworks.primary}"
        USE_TYPESCRIPT="${toString config.web.frameworks.typescript}"
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
        
        # Framework checks
        if command -v frameworks-health &> /dev/null; then
          frameworks-health
          echo ""
        fi
        
        # Desktop development check
        ${optionalString config.web.features.desktop ''
        if command -v desktop-health &> /dev/null; then
          desktop-health
          echo ""
        fi
        ''}
        
        # Overall configuration
        echo "📊 Overall Configuration:"
        echo "Profile: ${config.web.profile}"
        echo "Primary framework: ${config.web.frameworks.primary}"
        echo "Features enabled:"
        echo "  Core: ${if config.web.features.core then "✅" else "❌"}"
        echo "  Frameworks: ${if config.web.features.frameworks then "✅" else "❌"}"
        echo "  Desktop: ${if config.web.features.desktop then "✅" else "❌"}"
        echo "  Tooling: ${if config.web.features.tooling then "✅" else "❌"}"
        
        echo ""
        echo "✅ Web development environment health check completed!"
      '';
    };
  };
}