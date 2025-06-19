# DevContainer Templates and Management
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.containers;
in
{
  config = mkIf cfg.enable {
    # Enhanced container management tools
    home-manager.users.yuki.home.file = {
      "bin/devcontainer-templates" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          # DevContainer Template Manager
          set -euo pipefail
          
          COMMAND="''${1:-list}"
          PROJECT_DIR="''${2:-.}"
          
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
          
          case "$COMMAND" in
            "list")
              log_info "Available DevContainer Templates:"
              echo "========================="
              echo "📦 Node.js/TypeScript - Modern web development"
              echo "🐍 Python - Data science and web development"
              echo "🦀 Rust - Systems programming"
              echo "🐹 Go - Cloud native development"
              echo "☕ Java - Enterprise development"
              echo "💎 Ruby - Web development"
              echo "🐘 PHP - Web development"
              echo "🅒 C/C++ - Systems programming"
              echo "🚀 Full-stack - Multi-language development"
              ;;
              
            "create")
              TEMPLATE="''${3:-}"
              if [[ -z "$TEMPLATE" ]]; then
                log_error "Template name required"
                echo "Usage: devcontainer-templates create <project-dir> <template>"
                echo "Run 'devcontainer-templates list' to see available templates"
                exit 1
              fi
              
              log_info "Creating DevContainer for $TEMPLATE in $PROJECT_DIR"
              mkdir -p "$PROJECT_DIR/.devcontainer"
              
              case "$TEMPLATE" in
                "node"|"nodejs"|"typescript")
                  cat > "$PROJECT_DIR/.devcontainer/devcontainer.json" << 'EOF'
          {
            "name": "Node.js Development",
            "image": "mcr.microsoft.com/devcontainers/typescript-node:18",
            "features": {
              "ghcr.io/devcontainers/features/git:1": {},
              "ghcr.io/devcontainers/features/github-cli:1": {},
              "ghcr.io/devcontainers/features/docker-in-docker:2": {}
            },
            "customizations": {
              "vscode": {
                "extensions": [
                  "ms-vscode.vscode-typescript-next",
                  "esbenp.prettier-vscode",
                  "bradlc.vscode-tailwindcss",
                  "ms-vscode.vscode-json"
                ],
                "settings": {
                  "editor.formatOnSave": true,
                  "editor.defaultFormatter": "esbenp.prettier-vscode"
                }
              }
            },
            "forwardPorts": [3000, 8080, 5000],
            "postCreateCommand": "npm install",
            "remoteUser": "node"
          }
          EOF
                  ;;
                  
                "python")
                  cat > "$PROJECT_DIR/.devcontainer/devcontainer.json" << 'EOF'
          {
            "name": "Python Development",
            "image": "mcr.microsoft.com/devcontainers/python:3.11",
            "features": {
              "ghcr.io/devcontainers/features/git:1": {},
              "ghcr.io/devcontainers/features/github-cli:1": {}
            },
            "customizations": {
              "vscode": {
                "extensions": [
                  "ms-python.python",
                  "ms-python.pylint",
                  "ms-python.black-formatter",
                  "ms-toolsai.jupyter"
                ],
                "settings": {
                  "python.defaultInterpreterPath": "/usr/local/bin/python",
                  "python.formatting.provider": "black"
                }
              }
            },
            "forwardPorts": [8000, 5000, 8080],
            "postCreateCommand": "pip install -r requirements.txt || echo 'No requirements.txt found'",
            "remoteUser": "vscode"
          }
          EOF
                  ;;
                  
                "go")
                  cat > "$PROJECT_DIR/.devcontainer/devcontainer.json" << 'EOF'
          {
            "name": "Go Development",
            "image": "mcr.microsoft.com/devcontainers/go:1.21",
            "features": {
              "ghcr.io/devcontainers/features/git:1": {},
              "ghcr.io/devcontainers/features/github-cli:1": {},
              "ghcr.io/devcontainers/features/docker-in-docker:2": {}
            },
            "customizations": {
              "vscode": {
                "extensions": [
                  "golang.go",
                  "ms-vscode.vscode-json"
                ],
                "settings": {
                  "go.useCodeSnippetsOnFunctionSuggest": true,
                  "go.gopath": "/go",
                  "go.goroot": "/usr/local/go"
                }
              }
            },
            "forwardPorts": [8080, 9000],
            "postCreateCommand": "go mod download || echo 'No go.mod found'",
            "remoteUser": "vscode"
          }
          EOF
                  ;;
                  
                "rust")
                  cat > "$PROJECT_DIR/.devcontainer/devcontainer.json" << 'EOF'
          {
            "name": "Rust Development",
            "image": "mcr.microsoft.com/devcontainers/rust:latest",
            "features": {
              "ghcr.io/devcontainers/features/git:1": {},
              "ghcr.io/devcontainers/features/github-cli:1": {}
            },
            "customizations": {
              "vscode": {
                "extensions": [
                  "rust-lang.rust-analyzer",
                  "vadimcn.vscode-lldb"
                ]
              }
            },
            "forwardPorts": [8000, 3000],
            "postCreateCommand": "rustc --version && cargo --version",
            "remoteUser": "vscode"
          }
          EOF
                  ;;
                  
                "full-stack")
                  cat > "$PROJECT_DIR/.devcontainer/devcontainer.json" << 'EOF'
          {
            "name": "Full-Stack Development",
            "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
            "features": {
              "ghcr.io/devcontainers/features/node:1": {"version": "18"},
              "ghcr.io/devcontainers/features/python:1": {"version": "3.11"},
              "ghcr.io/devcontainers/features/go:1": {"version": "1.21"},
              "ghcr.io/devcontainers/features/git:1": {},
              "ghcr.io/devcontainers/features/github-cli:1": {},
              "ghcr.io/devcontainers/features/docker-in-docker:2": {}
            },
            "customizations": {
              "vscode": {
                "extensions": [
                  "ms-vscode.vscode-typescript-next",
                  "ms-python.python",
                  "golang.go",
                  "esbenp.prettier-vscode",
                  "ms-vscode.vscode-json"
                ]
              }
            },
            "forwardPorts": [3000, 8000, 8080, 5000],
            "remoteUser": "vscode"
          }
          EOF
                  ;;
                  
                *)
                  log_error "Unknown template: $TEMPLATE"
                  echo "Available templates: node, python, go, rust, full-stack"
                  exit 1
                  ;;
              esac
              
              # Create .devcontainer directory structure
              mkdir -p "$PROJECT_DIR/.devcontainer/.vscode"
              
              # Create launch.json for debugging
              cat > "$PROJECT_DIR/.devcontainer/.vscode/launch.json" << 'EOF'
          {
            "version": "0.2.0",
            "configurations": [
              {
                "name": "Debug Application",
                "type": "node",
                "request": "launch",
                "program": "''${workspaceFolder}/index.js",
                "console": "integratedTerminal",
                "internalConsoleOptions": "neverOpen"
              }
            ]
          }
          EOF
              
              log_success "DevContainer created successfully for $TEMPLATE"
              log_info "Next steps:"
              echo "  1. Open project in VS Code"
              echo "  2. Install 'Dev Containers' extension"
              echo "  3. Run 'Reopen in Container' command"
              ;;
              
            "status")
              log_info "DevContainer Status for $PROJECT_DIR"
              echo "============================="
              
              if [[ -f "$PROJECT_DIR/.devcontainer/devcontainer.json" ]]; then
                log_success "DevContainer configuration found"
                
                # Check if VS Code is available
                if command -v code &> /dev/null; then
                  echo "  ✅ VS Code: Available"
                else
                  echo "  ❌ VS Code: Not found"
                fi
                
                # Check Docker
                if command -v docker &> /dev/null && docker info &> /dev/null; then
                  echo "  ✅ Docker: Running"
                else
                  echo "  ❌ Docker: Not available"
                fi
                
                # Show container info
                if command -v jq &> /dev/null; then
                  NAME=$(jq -r '.name // "Unknown"' "$PROJECT_DIR/.devcontainer/devcontainer.json")
                  IMAGE=$(jq -r '.image // "Unknown"' "$PROJECT_DIR/.devcontainer/devcontainer.json")
                  echo "  📦 Container: $NAME"
                  echo "  🐳 Image: $IMAGE"
                fi
              else
                log_warning "No DevContainer configuration found"
                echo "  Run 'devcontainer-templates create . <template>' to create one"
              fi
              ;;
              
            "clean")
              log_info "Cleaning DevContainer resources"
              
              # Remove stopped containers
              if command -v docker &> /dev/null; then
                STOPPED=$(docker ps -a -q --filter "label=devcontainer" 2>/dev/null || echo "")
                if [[ -n "$STOPPED" ]]; then
                  docker rm $STOPPED
                  log_success "Removed stopped DevContainers"
                else
                  log_info "No stopped DevContainers found"
                fi
                
                # Remove unused images (with confirmation)
                read -p "Remove unused DevContainer images? [y/N]: " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                  docker image prune -f --filter "label=devcontainer"
                  log_success "Cleaned unused DevContainer images"
                fi
              fi
              ;;
              
            "help"|*)
              echo "DevContainer Template Manager"
              echo "============================="
              echo ""
              echo "Usage: devcontainer-templates <command> [options]"
              echo ""
              echo "Commands:"
              echo "  list                    List available templates"
              echo "  create <dir> <template> Create DevContainer from template"
              echo "  status [dir]            Show DevContainer status"
              echo "  clean                   Clean DevContainer resources"
              echo "  help                    Show this help"
              echo ""
              echo "Examples:"
              echo "  devcontainer-templates create ./my-project node"
              echo "  devcontainer-templates status ./my-project"
              ;;
          esac
        '';
      };
      
      "bin/devcontainer-images" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          # DevContainer Image Manager
          set -euo pipefail
          
          COMMAND="''${1:-status}"
          
          log_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }
          log_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
          log_warning() { echo -e "\033[1;33m⚠️  $1\033[0m"; }
          
          case "$COMMAND" in
            "pull")
              log_info "Pre-pulling DevContainer images"
              
              ${lib.concatStringsSep "\n" (map (image: 
                "echo \"📦 Pulling ${image}...\"; docker pull ${image} || log_warning \"Failed to pull ${image}\""
              ) cfg.commonImages)}
              
              ${lib.concatStringsSep "\n" (map (image: 
                "echo \"📦 Pulling ${image}...\"; docker pull ${image} || log_warning \"Failed to pull ${image}\""
              ) cfg.prebuiltImages)}
              
              log_success "Image pre-pulling completed"
              ;;
              
            "status")
              log_info "DevContainer Images Status"
              echo "========================="
              
              if command -v docker &> /dev/null; then
                echo "📊 Docker images:"
                docker images --filter "reference=mcr.microsoft.com/devcontainers/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
                
                echo ""
                echo "💾 Disk usage:"
                docker system df
              else
                log_warning "Docker not available"
              fi
              ;;
              
            "update")
              log_info "Updating DevContainer images"
              
              # Pull latest versions
              $0 pull
              
              # Remove old versions
              docker image prune -f
              
              log_success "DevContainer images updated"
              ;;
              
            *)
              echo "DevContainer Image Manager"
              echo "Usage: devcontainer-images <command>"
              echo ""
              echo "Commands:"
              echo "  pull    Pre-pull all configured images"
              echo "  status  Show image status and disk usage"
              echo "  update  Update all images to latest versions"
              ;;
          esac
        '';
      };
    };
  };
}