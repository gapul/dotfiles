# Multi-Template Workspace Management
# Combines multiple development templates for complex projects

{ lib, pkgs, ... }:

let
  utils = import ./utils.nix { inherit lib pkgs; };

  # Common workspace configurations
  workspaceConfigs = {
    fullstack-web = {
      name = "Fullstack Web Application";
      description = "Frontend + Backend + Database";
      templates = [ "web/nextjs-fullstack" "web/node-api" ];
      services = [ "postgresql" "redis" ];
      ports = {
        frontend = 3000;
        backend = 8000;
        database = 5432;
        cache = 6379;
      };
    };

    mobile-backend = {
      name = "Mobile App with Backend";
      description = "React Native/Flutter + API + Database";
      templates = [ "mobile/react-native" "web/node-api" ];
      services = [ "postgresql" "redis" ];
      ports = {
        mobile = 8081;
        backend = 8000;
        database = 5432;
        cache = 6379;
      };
    };

    ml-platform = {
      name = "ML Platform";
      description = "ML Development + Web Interface + API";
      templates = [ "data/python-ml" "web/nextjs-fullstack" "web/node-api" ];
      services = [ "postgresql" "redis" "jupyter" "mlflow" ];
      ports = {
        jupyter = 8888;
        mlflow = 5000;
        frontend = 3000;
        backend = 8000;
        database = 5432;
        cache = 6379;
      };
    };

    microservices = {
      name = "Microservices Architecture";
      description = "Multiple APIs + Frontend + Container Orchestration";
      templates = [ "web/docker-fullstack" "web/node-api" "systems/go-api" ];
      services = [ "postgresql" "redis" "nginx" "docker" ];
      ports = {
        frontend = 3000;
        api_gateway = 8000;
        user_service = 8001;
        auth_service = 8002;
        database = 5432;
        cache = 6379;
      };
    };

    data-pipeline = {
      name = "Data Pipeline";
      description = "Data Processing + Analytics + Dashboard";
      templates = [ "data/python-ml" "data/r-analytics" "web/nextjs-fullstack" ];
      services = [ "postgresql" "redis" "jupyter" ];
      ports = {
        jupyter = 8888;
        rstudio = 8787;
        dashboard = 3000;
        database = 5432;
        cache = 6379;
      };
    };

    cross-platform = {
      name = "Cross-Platform Development";
      description = "React Native + Flutter + Shared Backend";
      templates = [ "mobile/react-native" "mobile/flutter" "web/node-api" ];
      services = [ "postgresql" "redis" ];
      ports = {
        react_native = 8081;
        flutter = 8080;
        backend = 8000;
        database = 5432;
        cache = 6379;
      };
    };
  };

  # Workspace management functions
  mkWorkspaceScript = pkgs.writeShellScriptBin "workspace" ''
    set -e
    
    WORKSPACE_DIR="$HOME/.local/share/workspaces"
    TEMPLATES_DIR="${toString ../.}"
    
    # Ensure workspace directory exists
    mkdir -p "$WORKSPACE_DIR"
    
    case "$1" in
      list)
        echo "🏗️ Available Workspace Configurations"
        echo "════════════════════════════════════════════════════════════════════════════════"
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: config: ''
        echo "📦 ${name}"
        echo "   Name: ${config.name}"
        echo "   Description: ${config.description}"
        echo "   Templates: ${lib.concatStringsSep ", " config.templates}"
        echo "   Services: ${lib.concatStringsSep ", " config.services}"
        echo ""
        '') workspaceConfigs)}
        ;;
      
      create)
        if [ -z "$2" ] || [ -z "$3" ]; then
          echo "Usage: workspace create <config-name> <project-name>"
          echo ""
          echo "Available configurations:"
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: "echo \"  ${name}\"") workspaceConfigs)}
          exit 1
        fi
        
        config_name="$2"
        project_name="$3"
        workspace_dir="$WORKSPACE_DIR/$project_name"
        
        if [ -d "$workspace_dir" ]; then
          echo "❌ Workspace '$project_name' already exists"
          exit 1
        fi
        
        echo "🚀 Creating workspace: $project_name ($config_name)"
        mkdir -p "$workspace_dir"
        cd "$workspace_dir"
        
        # Create workspace configuration
        cat > workspace.json << EOF
    {
      "name": "$project_name",
      "config": "$config_name",
      "created": "$(date -Iseconds)",
      "templates": [],
      "services": [],
      "ports": {}
    }
    EOF
        
        # Create README
        cat > README.md << EOF
    # $project_name
    
    Multi-template workspace using configuration: **$config_name**
    
    ## Quick Start
    
    \`\`\`bash
    # Enter workspace
    cd $workspace_dir
    workspace enter
    
    # Start all services
    workspace start
    
    # View status
    workspace status
    \`\`\`
    
    ## Services
    
    - Check \`workspace status\` for service URLs and ports
    
    ## Development
    
    Each component has its own directory with standard commands:
    - \`<template>-dev dev\` - Start development server
    - \`<template>-dev test\` - Run tests
    - \`<template>-dev build\` - Build for production
    EOF
        
        # Initialize based on configuration
        case "$config_name" in
          fullstack-web)
            mkdir -p frontend backend
            echo "📁 Created: frontend/, backend/"
            echo "💡 Next steps:"
            echo "  cd frontend && nix develop $TEMPLATES_DIR/web/nextjs-fullstack"
            echo "  cd backend && nix develop $TEMPLATES_DIR/web/node-api"
            ;;
          mobile-backend)
            mkdir -p mobile backend
            echo "📁 Created: mobile/, backend/"
            echo "💡 Next steps:"
            echo "  cd mobile && nix develop $TEMPLATES_DIR/mobile/react-native"
            echo "  cd backend && nix develop $TEMPLATES_DIR/web/node-api"
            ;;
          ml-platform)
            mkdir -p ml-models web-interface api
            echo "📁 Created: ml-models/, web-interface/, api/"
            echo "💡 Next steps:"
            echo "  cd ml-models && nix develop $TEMPLATES_DIR/data/python-ml"
            echo "  cd web-interface && nix develop $TEMPLATES_DIR/web/nextjs-fullstack"
            echo "  cd api && nix develop $TEMPLATES_DIR/web/node-api"
            ;;
          microservices)
            mkdir -p services/{user-service,auth-service,api-gateway} frontend infrastructure
            echo "📁 Created: services/, frontend/, infrastructure/"
            echo "💡 Next steps:"
            echo "  cd infrastructure && nix develop $TEMPLATES_DIR/web/docker-fullstack"
            echo "  cd services/user-service && nix develop $TEMPLATES_DIR/web/node-api"
            echo "  cd services/auth-service && nix develop $TEMPLATES_DIR/systems/go-api"
            ;;
          data-pipeline)
            mkdir -p data-processing analytics dashboard
            echo "📁 Created: data-processing/, analytics/, dashboard/"
            echo "💡 Next steps:"
            echo "  cd data-processing && nix develop $TEMPLATES_DIR/data/python-ml"
            echo "  cd analytics && nix develop $TEMPLATES_DIR/data/r-analytics"
            echo "  cd dashboard && nix develop $TEMPLATES_DIR/web/nextjs-fullstack"
            ;;
          cross-platform)
            mkdir -p react-native flutter backend
            echo "📁 Created: react-native/, flutter/, backend/"
            echo "💡 Next steps:"
            echo "  cd react-native && nix develop $TEMPLATES_DIR/mobile/react-native"
            echo "  cd flutter && nix develop $TEMPLATES_DIR/mobile/flutter"
            echo "  cd backend && nix develop $TEMPLATES_DIR/web/node-api"
            ;;
          *)
            echo "❌ Unknown configuration: $config_name"
            rm -rf "$workspace_dir"
            exit 1
            ;;
        esac
        
        echo "✅ Workspace created: $workspace_dir"
        ;;
      
      enter)
        if [ ! -f "workspace.json" ]; then
          echo "❌ No workspace found in current directory"
          echo "💡 Run 'workspace create' to create a new workspace"
          exit 1
        fi
        
        project_name=$(jq -r '.name' workspace.json)
        config_name=$(jq -r '.config' workspace.json)
        
        echo "🏗️ Entering workspace: $project_name ($config_name)"
        
        # Start services automatically
        workspace start
        
        # Show status
        workspace status
        ;;
      
      start)
        if [ ! -f "workspace.json" ]; then
          echo "❌ No workspace found in current directory"
          exit 1
        fi
        
        config_name=$(jq -r '.config' workspace.json)
        echo "🚀 Starting services for workspace configuration: $config_name"
        
        # Start common services
        start_services() {
          # PostgreSQL
          if ! pg_ctl status > /dev/null 2>&1; then
            export PGDATA="$PWD/.postgres"
            if [ ! -d "$PGDATA" ]; then
              initdb "$PGDATA" --auth-host=trust --auth-local=trust
            fi
            pg_ctl start -l "$PGDATA/server.log"
            echo "✅ PostgreSQL started"
          fi
          
          # Redis
          if ! redis-cli ping > /dev/null 2>&1; then
            redis-server --daemonize yes --port 6379
            echo "✅ Redis started"
          fi
        }
        
        start_services
        echo "✅ All services started"
        ;;
      
      stop)
        echo "🛑 Stopping all services..."
        
        # Stop PostgreSQL
        if pg_ctl status > /dev/null 2>&1; then
          pg_ctl stop
          echo "✅ PostgreSQL stopped"
        fi
        
        # Stop Redis
        if redis-cli ping > /dev/null 2>&1; then
          redis-cli shutdown
          echo "✅ Redis stopped"
        fi
        ;;
      
      status)
        if [ ! -f "workspace.json" ]; then
          echo "❌ No workspace found in current directory"
          exit 1
        fi
        
        project_name=$(jq -r '.name' workspace.json)
        config_name=$(jq -r '.config' workspace.json)
        
        echo "📊 Workspace Status: $project_name ($config_name)"
        echo "════════════════════════════════════════════════════════════════════════════════"
        
        # Check services
        echo "🔧 Services:"
        if pg_ctl status > /dev/null 2>&1; then
          echo "  ✅ PostgreSQL (port 5432)"
        else
          echo "  ❌ PostgreSQL (stopped)"
        fi
        
        if redis-cli ping > /dev/null 2>&1; then
          echo "  ✅ Redis (port 6379)"
        else
          echo "  ❌ Redis (stopped)"
        fi
        
        # Check common ports
        echo ""
        echo "🌐 Common Ports:"
        for port in 3000 8000 8080 8081 8888 5000; do
          if nc -z localhost $port 2>/dev/null; then
            echo "  ✅ Port $port (in use)"
          else
            echo "  ⚪ Port $port (available)"
          fi
        done
        
        # Show directory structure
        echo ""
        echo "📁 Project Structure:"
        find . -maxdepth 2 -type d | grep -v '^\.$' | grep -v '.postgres' | sort
        ;;
      
      delete)
        if [ -z "$2" ]; then
          echo "Usage: workspace delete <project-name>"
          exit 1
        fi
        
        project_name="$2"
        workspace_dir="$WORKSPACE_DIR/$project_name"
        
        if [ ! -d "$workspace_dir" ]; then
          echo "❌ Workspace '$project_name' not found"
          exit 1
        fi
        
        echo "⚠️  Are you sure you want to delete workspace '$project_name'? (y/N)"
        read -r confirmation
        if [ "$confirmation" = "y" ] || [ "$confirmation" = "Y" ]; then
          rm -rf "$workspace_dir"
          echo "✅ Workspace '$project_name' deleted"
        else
          echo "❌ Deletion cancelled"
        fi
        ;;
      
      *)
        echo "🏗️ Multi-Template Workspace Manager"
        echo ""
        echo "Usage: workspace <command> [args]"
        echo ""
        echo "Commands:"
        echo "  list                    List available workspace configurations"
        echo "  create <config> <name>  Create new multi-template workspace"
        echo "  enter                   Enter current workspace (start services)"
        echo "  start                   Start workspace services"
        echo "  stop                    Stop workspace services"
        echo "  status                  Show workspace status"
        echo "  delete <name>           Delete workspace"
        echo ""
        echo "Workspace Configurations:"
        echo "  fullstack-web          Frontend + Backend + Database"
        echo "  mobile-backend         Mobile App + API + Database"
        echo "  ml-platform            ML Development + Web Interface + API"
        echo "  microservices          Multiple APIs + Frontend + Containers"
        echo "  data-pipeline          Data Processing + Analytics + Dashboard"
        echo "  cross-platform         React Native + Flutter + Backend"
        echo ""
        echo "Examples:"
        echo "  workspace create fullstack-web myproject"
        echo "  workspace create ml-platform ai-platform"
        echo "  workspace create microservices ecommerce"
        ;;
    esac
  '';

  # Multi-terminal session manager
  mkSessionScript = pkgs.writeShellScriptBin "dev-session" ''
    set -e
    
    if [ ! -f "workspace.json" ]; then
      echo "❌ No workspace found. Run 'workspace create' first."
      exit 1
    fi
    
    project_name=$(jq -r '.name' workspace.json)
    config_name=$(jq -r '.config' workspace.json)
    
    echo "🚀 Starting development session for: $project_name ($config_name)"
    
    case "$config_name" in
      fullstack-web)
        echo "Opening terminals for frontend and backend..."
        # Frontend terminal
        osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/frontend' && nix develop ${toString ../.}/web/nextjs-fullstack\""
        # Backend terminal  
        osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/backend' && nix develop ${toString ../.}/web/node-api\""
        ;;
      mobile-backend)
        echo "Opening terminals for mobile and backend..."
        osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/mobile' && nix develop ${toString ../.}/mobile/react-native\""
        osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/backend' && nix develop ${toString ../.}/web/node-api\""
        ;;
      ml-platform)
        echo "Opening terminals for ML, web interface, and API..."
        osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/ml-models' && nix develop ${toString ../.}/data/python-ml\""
        osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/web-interface' && nix develop ${toString ../.}/web/nextjs-fullstack\""
        osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/api' && nix develop ${toString ../.}/web/node-api\""
        ;;
      *)
        echo "💡 Manual setup required for configuration: $config_name"
        echo "Check the README.md for component-specific commands."
        ;;
    esac
    
    echo "✅ Development session started!"
  '';

in {
  inherit workspaceConfigs;
  
  # Main workspace management
  workspace = mkWorkspaceScript;
  
  # Session management
  devSession = mkSessionScript;
  
  # Utility functions
  getWorkspaceConfig = name: workspaceConfigs.${name} or null;
  
  listWorkspaceConfigs = lib.mapAttrsToList (name: config: {
    inherit name;
    inherit (config) description templates services ports;
  }) workspaceConfigs;
  
  # Combined environment for workspace management
  workspaceEnv = pkgs.mkShell {
    name = "multi-template-workspace";
    
    buildInputs = with pkgs; [
      # Workspace management
      mkWorkspaceScript
      mkSessionScript
      
      # Common dependencies
      git
      jq
      netcat-gnu
      
      # Database services
      postgresql
      redis
      
      # Additional utilities
      curl
    ];
    
    shellHook = ''
      echo "🏗️ Multi-Template Workspace Environment"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "🛠️ Available commands:"
      echo "  workspace         # Workspace management"
      echo "  dev-session       # Multi-terminal session starter"
      echo ""
      echo "📚 Quick start:"
      echo "  workspace list                        # See available configurations"
      echo "  workspace create fullstack-web myapp  # Create workspace"
      echo "  cd ~/.local/share/workspaces/myapp    # Enter workspace"
      echo "  workspace enter                       # Start services"
      echo "  dev-session                           # Open development terminals"
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    '';
  };
}