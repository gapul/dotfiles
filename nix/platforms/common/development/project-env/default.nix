{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.project-env;
in
{
  options.dotfiles.development.project-env = {
    enable = mkEnableOption "Project-specific environment automation";
    
    autoDetection = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically detect and setup project environments";
    };
    
    supportedTypes = mkOption {
      type = types.listOf (types.enum [
        "nodejs" "python" "rust" "go" "php" "ruby" 
        "java" "kotlin" "swift" "cpp" "dotnet"
        "flutter" "react" "nextjs" "vue" "angular"
        "docker" "terraform" "ansible"
      ]);
      default = [ "nodejs" "python" "rust" "go" "react" "nextjs" "docker" ];
      description = "Supported project types for auto-setup";
    };
    
    direnvIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable direnv integration for automatic environment loading";
    };
    
    shellIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable shell integration for project environment commands";
    };
    
    vscodeIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Generate VS Code workspace settings for projects";
    };
    
    templatePath = mkOption {
      type = types.str;
      default = "$HOME/.config/project-templates";
      description = "Path to project templates directory";
    };
  };

  config = mkIf cfg.enable {
    # Core packages for project environment management
    home.packages = with pkgs; [
      # Environment management
      direnv
      nix-direnv
      
      # Project initialization tools
      cookiecutter
      copier
      
      # Language-specific tools based on supported types
    ] ++ optionals (elem "nodejs" cfg.supportedTypes) [
      nodejs
      nodePackages.npm
      nodePackages.yarn
      nodePackages.pnpm
      nodePackages.create-react-app
      nodePackages.create-next-app
    ] ++ optionals (elem "python" cfg.supportedTypes) [
      python3
      python3Packages.pip
      python3Packages.virtualenv
      python3Packages.poetry
      python3Packages.pipenv
    ] ++ optionals (elem "rust" cfg.supportedTypes) [
      rustc
      cargo
      rustfmt
      clippy
    ] ++ optionals (elem "go" cfg.supportedTypes) [
      go
      gofmt
      golint
    ] ++ optionals (elem "docker" cfg.supportedTypes) [
      docker
      docker-compose
    ];

    # Direnv configuration
    programs.direnv = mkIf cfg.direnvIntegration {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
      config = {
        global = {
          hide_env_diff = true;
          warn_timeout = "24h";
        };
      };
    };

    # Project environment templates
    home.file."${cfg.templatePath}" = {
      recursive = true;
      source = ./templates;
    };

    # Project initialization script
    home.file."bin/project-init" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Project Environment Auto-Setup
        set -euo pipefail
        
        PROJECT_NAME="$1"
        PROJECT_TYPE="''${2:-auto}"
        PROJECT_DIR="''${3:-./}"
        
        # Colors for output
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m'
        
        log_info() { echo -e "''${BLUE}ℹ️  $1''${NC}"; }
        log_success() { echo -e "''${GREEN}✅ $1''${NC}"; }
        log_warning() { echo -e "''${YELLOW}⚠️  $1''${NC}"; }
        log_error() { echo -e "''${RED}❌ $1''${NC}"; }
        
        # Auto-detect project type if not specified
        detect_project_type() {
          local dir="$1"
          
          if [[ -f "$dir/package.json" ]]; then
            if grep -q "next" "$dir/package.json"; then
              echo "nextjs"
            elif grep -q "react" "$dir/package.json"; then
              echo "react"
            elif grep -q "vue" "$dir/package.json"; then
              echo "vue"
            elif grep -q "angular" "$dir/package.json"; then
              echo "angular"
            else
              echo "nodejs"
            fi
          elif [[ -f "$dir/Cargo.toml" ]]; then
            echo "rust"
          elif [[ -f "$dir/go.mod" ]]; then
            echo "go"
          elif [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/setup.py" ]]; then
            echo "python"
          elif [[ -f "$dir/Dockerfile" ]]; then
            echo "docker"
          elif [[ -f "$dir/composer.json" ]]; then
            echo "php"
          elif [[ -f "$dir/Gemfile" ]]; then
            echo "ruby"
          elif [[ -f "$dir/pubspec.yaml" ]]; then
            echo "flutter"
          else
            echo "unknown"
          fi
        }
        
        # Create directory if it doesn't exist
        if [[ ! -d "$PROJECT_DIR" ]]; then
          mkdir -p "$PROJECT_DIR"
        fi
        
        cd "$PROJECT_DIR"
        
        # Auto-detect if type is 'auto'
        if [[ "$PROJECT_TYPE" == "auto" ]]; then
          PROJECT_TYPE=$(detect_project_type ".")
          if [[ "$PROJECT_TYPE" == "unknown" ]]; then
            log_warning "Could not auto-detect project type. Using 'nodejs' as default."
            PROJECT_TYPE="nodejs"
          else
            log_info "Detected project type: $PROJECT_TYPE"
          fi
        fi
        
        log_info "Setting up $PROJECT_TYPE project: $PROJECT_NAME"
        
        # Create .envrc for direnv
        ${if cfg.direnvIntegration then ''
          if [[ ! -f .envrc ]]; then
            cat > .envrc << EOF
        # Auto-generated by project-init
        use nix
        
        # Project-specific environment variables
        export PROJECT_NAME="$PROJECT_NAME"
        export PROJECT_TYPE="$PROJECT_TYPE"
        
        # Load project-specific configuration
        if [[ -f .env.local ]]; then
          dotenv .env.local
        fi
        EOF
            log_success "Created .envrc for direnv"
          fi
        '' else ""}
        
        # Create shell.nix based on project type
        if [[ ! -f shell.nix ]]; then
          case "$PROJECT_TYPE" in
            "nodejs"|"react"|"nextjs"|"vue"|"angular")
              cat > shell.nix << 'EOF'
        { pkgs ? import <nixpkgs> {} }:
        
        pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs
            nodePackages.npm
            nodePackages.yarn
            nodePackages.pnpm
            nodePackages.typescript
            nodePackages.eslint
            nodePackages.prettier
          ];
          
          shellHook = '''
            echo "🚀 Node.js development environment ready!"
            echo "Node: $(node --version)"
            echo "NPM: $(npm --version)"
          ''';
        }
        EOF
              ;;
            "python")
              cat > shell.nix << 'EOF'
        { pkgs ? import <nixpkgs> {} }:
        
        pkgs.mkShell {
          buildInputs = with pkgs; [
            python3
            python3Packages.pip
            python3Packages.virtualenv
            python3Packages.poetry
            python3Packages.black
            python3Packages.flake8
            python3Packages.pytest
          ];
          
          shellHook = '''
            echo "🐍 Python development environment ready!"
            echo "Python: $(python --version)"
            echo "Pip: $(pip --version)"
          ''';
        }
        EOF
              ;;
            "rust")
              cat > shell.nix << 'EOF'
        { pkgs ? import <nixpkgs> {} }:
        
        pkgs.mkShell {
          buildInputs = with pkgs; [
            rustc
            cargo
            rustfmt
            clippy
            rust-analyzer
          ];
          
          shellHook = '''
            echo "🦀 Rust development environment ready!"
            echo "Rust: $(rustc --version)"
            echo "Cargo: $(cargo --version)"
          ''';
        }
        EOF
              ;;
            "go")
              cat > shell.nix << 'EOF'
        { pkgs ? import <nixpkgs> {} }:
        
        pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            gofmt
            golint
            gopls
          ];
          
          shellHook = '''
            echo "🐹 Go development environment ready!"
            echo "Go: $(go version)"
          ''';
        }
        EOF
              ;;
            "docker")
              cat > shell.nix << 'EOF'
        { pkgs ? import <nixpkgs> {} }:
        
        pkgs.mkShell {
          buildInputs = with pkgs; [
            docker
            docker-compose
            docker-buildx
          ];
          
          shellHook = '''
            echo "🐳 Docker development environment ready!"
            echo "Docker: $(docker --version)"
            echo "Docker Compose: $(docker-compose --version)"
          ''';
        }
        EOF
              ;;
            *)
              cat > shell.nix << 'EOF'
        { pkgs ? import <nixpkgs> {} }:
        
        pkgs.mkShell {
          buildInputs = with pkgs; [
            git
            curl
            jq
          ];
          
          shellHook = '''
            echo "⚙️  Generic development environment ready!"
          ''';
        }
        EOF
              ;;
          esac
          log_success "Created shell.nix for $PROJECT_TYPE"
        fi
        
        # Create VS Code workspace settings
        ${if cfg.vscodeIntegration then ''
          if [[ ! -d .vscode ]]; then
            mkdir -p .vscode
            
            cat > .vscode/settings.json << EOF
        {
          "files.exclude": {
            "**/node_modules": true,
            "**/.git": true,
            "**/result": true,
            "**/result-*": true
          },
          "search.exclude": {
            "**/node_modules": true,
            "**/result": true,
            "**/result-*": true
          },
          "editor.formatOnSave": true,
          "editor.codeActionsOnSave": {
            "source.fixAll": true
          }
        }
        EOF
            
            # Project type specific VS Code settings
            case "$PROJECT_TYPE" in
              "nodejs"|"react"|"nextjs"|"vue"|"angular")
                cat > .vscode/extensions.json << 'EOF'
        {
          "recommendations": [
            "ms-vscode.vscode-typescript-next",
            "esbenp.prettier-vscode",
            "dbaeumer.vscode-eslint",
            "bradlc.vscode-tailwindcss",
            "ms-vscode.vscode-json"
          ]
        }
        EOF
                ;;
              "python")
                cat > .vscode/extensions.json << 'EOF'
        {
          "recommendations": [
            "ms-python.python",
            "ms-python.black-formatter",
            "ms-python.flake8",
            "ms-python.isort"
          ]
        }
        EOF
                ;;
              "rust")
                cat > .vscode/extensions.json << 'EOF'
        {
          "recommendations": [
            "rust-lang.rust-analyzer",
            "serayuzgur.crates",
            "vadimcn.vscode-lldb"
          ]
        }
        EOF
                ;;
            esac
            
            log_success "Created VS Code workspace configuration"
          fi
        '' else ""}
        
        # Create basic project files if they don't exist
        if [[ ! -f README.md ]]; then
          cat > README.md << EOF
        # $PROJECT_NAME
        
        A $PROJECT_TYPE project initialized with Nix development environment.
        
        ## Development Setup
        
        This project uses Nix for reproducible development environments.
        
        ### Prerequisites
        
        - Nix package manager
        - direnv (optional but recommended)
        
        ### Getting Started
        
        1. Clone the repository
        2. Enter the directory: \`cd $PROJECT_NAME\`
        3. If using direnv: \`direnv allow\`
        4. Otherwise: \`nix develop\`
        
        ## Project Structure
        
        - \`.envrc\` - direnv configuration
        - \`shell.nix\` - Nix development environment
        - \`.vscode/\` - VS Code workspace settings
        
        EOF
          log_success "Created README.md"
        fi
        
        # Create .gitignore if it doesn't exist
        if [[ ! -f .gitignore ]]; then
          cat > .gitignore << 'EOF'
        # Nix
        result
        result-*
        
        # direnv
        .direnv/
        
        # OS
        .DS_Store
        Thumbs.db
        
        # IDE
        .vscode/settings.json
        .idea/
        
        # Environment
        .env.local
        .env.*.local
        EOF
          
          # Add project-type specific ignores
          case "$PROJECT_TYPE" in
            "nodejs"|"react"|"nextjs"|"vue"|"angular")
              cat >> .gitignore << 'EOF'
        
        # Node.js
        node_modules/
        npm-debug.log*
        yarn-debug.log*
        yarn-error.log*
        .npm
        .yarn-integrity
        
        # Next.js
        .next/
        out/
        build/
        dist/
        EOF
              ;;
            "python")
              cat >> .gitignore << 'EOF'
        
        # Python
        __pycache__/
        *.py[cod]
        *$py.class
        *.so
        .Python
        build/
        develop-eggs/
        dist/
        downloads/
        eggs/
        .eggs/
        lib/
        lib64/
        parts/
        sdist/
        var/
        wheels/
        *.egg-info/
        .installed.cfg
        *.egg
        
        # Virtual environments
        venv/
        env/
        ENV/
        EOF
              ;;
            "rust")
              cat >> .gitignore << 'EOF'
        
        # Rust
        /target/
        Cargo.lock
        **/*.rs.bk
        EOF
              ;;
            "go")
              cat >> .gitignore << 'EOF'
        
        # Go
        *.exe
        *.exe~
        *.dll
        *.so
        *.dylib
        *.test
        *.out
        go.work
        vendor/
        EOF
              ;;
          esac
          
          log_success "Created .gitignore"
        fi
        
        # Initialize git repository if not already initialized
        if [[ ! -d .git ]]; then
          git init
          git add .
          git commit -m "Initial commit: $PROJECT_TYPE project setup"
          log_success "Initialized git repository"
        fi
        
        log_success "Project setup complete!"
        log_info "Next steps:"
        log_info "  1. cd $(pwd)"
        ${if cfg.direnvIntegration then ''
          log_info "  2. direnv allow (to load environment automatically)"
        '' else ''
          log_info "  2. nix develop (to enter development shell)"
        ''}
        log_info "  3. Start developing! 🚀"
      '';
    };

    # Project environment health check
    home.file."bin/project-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🏥 Project Environment Health Check"
        echo "=================================="
        
        # Check direnv
        ${if cfg.direnvIntegration then ''
          if command -v direnv &> /dev/null; then
            echo "✅ direnv: Available"
            if [[ -f .envrc ]]; then
              echo "✅ .envrc: Found"
              if direnv status | grep -q "Found RC allowed true"; then
                echo "✅ direnv: Environment loaded"
              else
                echo "⚠️  direnv: Run 'direnv allow' to load environment"
              fi
            else
              echo "⚪ .envrc: Not found"
            fi
          else
            echo "❌ direnv: Not available"
          fi
        '' else ''
          echo "⚪ direnv: Integration disabled"
        ''}
        
        # Check Nix shell
        if [[ -f shell.nix ]]; then
          echo "✅ shell.nix: Found"
          if nix-instantiate --eval shell.nix --json &> /dev/null; then
            echo "✅ shell.nix: Valid"
          else
            echo "❌ shell.nix: Invalid syntax"
          fi
        else
          echo "⚪ shell.nix: Not found"
        fi
        
        # Check VS Code configuration
        ${if cfg.vscodeIntegration then ''
          if [[ -d .vscode ]]; then
            echo "✅ VS Code: Configuration found"
            if [[ -f .vscode/settings.json ]]; then
              echo "✅ VS Code: Settings configured"
            fi
            if [[ -f .vscode/extensions.json ]]; then
              echo "✅ VS Code: Extensions recommended"
            fi
          else
            echo "⚪ VS Code: No configuration"
          fi
        '' else ''
          echo "⚪ VS Code: Integration disabled"
        ''}
        
        # Check project type detection
        PROJECT_TYPE=$(${./scripts/detect-project-type.sh} . 2>/dev/null || echo "unknown")
        echo "🔍 Detected project type: $PROJECT_TYPE"
        
        # Check git status
        if [[ -d .git ]]; then
          echo "✅ Git: Repository initialized"
          if git status --porcelain | grep -q .; then
            echo "⚠️  Git: Uncommitted changes"
          else
            echo "✅ Git: Working directory clean"
          fi
        else
          echo "⚪ Git: Not initialized"
        fi
        
        echo ""
        echo "💡 Tips:"
        echo "  - Use 'project-init <name> <type>' to setup new projects"
        echo "  - Run 'nix develop' to enter development shell"
        echo "  - Check project templates in ${cfg.templatePath}"
      '';
    };

    # Shell integration
    programs.zsh.shellAliases = mkIf cfg.shellIntegration {
      proj-init = "project-init";
      proj-health = "project-health";
      proj-shell = "nix develop";
      proj-clean = "nix store gc && direnv reload";
    };

    # Shell functions for project management
    programs.zsh.initExtra = mkIf cfg.shellIntegration ''
      # Quick project directory navigation
      proj-cd() {
        local project_root
        project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
        cd "$project_root"
      }
      
      # Quick project type detection
      proj-type() {
        echo "Project type: $(${./scripts/detect-project-type.sh} .)"
      }
      
      # Project environment status
      proj-status() {
        echo "📁 Project: $(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
        echo "🏷️  Type: $(proj-type)"
        if command -v direnv &> /dev/null && [[ -f .envrc ]]; then
          echo "🔄 Environment: $(direnv status | grep "Found RC" || echo "Not loaded")"
        fi
        if [[ -f shell.nix ]]; then
          echo "❄️  Nix: shell.nix available"
        fi
      }
    '';
  };
}