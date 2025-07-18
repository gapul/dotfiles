# Shared utilities for development environment templates
# Common functions and configurations used across multiple templates

{ lib, pkgs, ... }:

rec {
  # Common development dependencies
  commonDevDeps = with pkgs; [
    git
    curl
    jq
    which
  ];

  # Common Node.js dependencies
  nodeDevDeps = with pkgs; [
    nodejs_20
    npm
    yarn
    pnpm
  ];

  # Common Python dependencies  
  pythonDevDeps = with pkgs; [
    python311
    python311Packages.pip
    python311Packages.virtualenv
  ];

  # Common container dependencies
  containerDeps = with pkgs; [
    docker
    docker-compose
  ];

  # Common database dependencies
  databaseDeps = with pkgs; [
    postgresql
    redis
    sqlite
  ];

  # Create a standard development script
  mkDevScript = name: commands: pkgs.writeShellScriptBin name ''
    case "$1" in
      ${lib.concatStringsSep "\n      " (lib.mapAttrsToList (cmd: script: ''
        ${cmd})
          echo "${script}"
          ;;'') commands)}
      *)
        echo "${name} Development Commands"
        echo ""
        echo "Usage: ${name} <command>"
        echo ""
        echo "Available commands:"
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList (cmd: _: "echo \"  ${cmd}\"") commands)}
        ;;
    esac
  '';

  # Create a setup script with common initialization
  mkSetupScript = name: extraSetup: pkgs.writeShellScriptBin "setup-${name}" ''
    set -e
    
    echo "🚀 Setting up ${name} development environment..."
    
    # Create common directories
    mkdir -p {src,tests,docs,scripts}
    
    # Initialize git if not exists
    if [ ! -d .git ]; then
      git init
      echo "✅ Git repository initialized"
    fi
    
    # Create basic .gitignore
    if [ ! -f .gitignore ]; then
      cat > .gitignore << 'EOF'
    # Dependencies
    node_modules/
    __pycache__/
    target/
    
    # IDE
    .vscode/
    .idea/
    *.swp
    *.swo
    
    # OS
    .DS_Store
    Thumbs.db
    
    # Environment
    .env
    .env.local
    
    # Build outputs
    dist/
    build/
    *.log
    EOF
      echo "✅ .gitignore created"
    fi
    
    ${extraSetup}
    
    echo "✅ ${name} environment ready!"
  '';

  # Standard shell hook for development environments
  mkShellHook = { name, version ? "", extraHook ? "" }: ''
    echo "🚀 ${name} Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ${lib.optionalString (version != "") ''echo "${name}: ${version}"''}
    echo "📂 Project: $PWD"
    echo ""
    ${extraHook}
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '';

  # Common environment variables
  commonEnvVars = {
    NODE_ENV = "development";
    GIT_EDITOR = "code --wait";
    TERM = "xterm-256color";
  };

  # Platform-specific dependencies
  darwinDeps = lib.optionals pkgs.stdenv.isDarwin (with pkgs; [
    darwin.apple_sdk.frameworks.Security
    darwin.apple_sdk.frameworks.CoreFoundation
    darwin.apple_sdk.frameworks.SystemConfiguration
  ]);

  linuxDeps = lib.optionals pkgs.stdenv.isLinux (with pkgs; [
    pkg-config
    openssl
  ]);

  # Create a standard mkShell with common configuration
  mkDevShell = { name, buildInputs ? [], shellHook ? "", extraEnv ? {} }: pkgs.mkShell {
    inherit name;
    
    buildInputs = commonDevDeps ++ darwinDeps ++ linuxDeps ++ buildInputs;
    
    shellHook = mkShellHook { 
      inherit name; 
      extraHook = shellHook; 
    };
    
    # Set environment variables
    inherit (commonEnvVars // extraEnv) NODE_ENV GIT_EDITOR TERM;
  };

  # Database service management functions
  dbServiceFunctions = ''
    # PostgreSQL service management
    start_postgres() {
      if [ ! -d "$PGDATA" ]; then
        echo "🗄️ Initializing PostgreSQL..."
        initdb "$PGDATA" --auth-host=trust --auth-local=trust
        echo "port = ''${PGPORT:-5432}" >> "$PGDATA/postgresql.conf"
      fi
      
      if ! pg_ctl status > /dev/null 2>&1; then
        pg_ctl start -l "$PGDATA/server.log"
        echo "✅ PostgreSQL started"
      fi
    }
    
    stop_postgres() {
      if pg_ctl status > /dev/null 2>&1; then
        pg_ctl stop
        echo "✅ PostgreSQL stopped"
      fi
    }
    
    # Redis service management  
    start_redis() {
      if ! redis-cli ping > /dev/null 2>&1; then
        redis-server --daemonize yes --port ''${REDIS_PORT:-6379}
        echo "✅ Redis started"
      fi
    }
    
    stop_redis() {
      if redis-cli ping > /dev/null 2>&1; then
        redis-cli shutdown
        echo "✅ Redis stopped"
      fi
    }
    
    # Start all services
    start_services() {
      echo "🚀 Starting development services..."
      start_postgres
      start_redis
    }
    
    # Stop all services
    stop_services() {
      echo "🛑 Stopping development services..."
      stop_postgres  
      stop_redis
    }
    
    # Cleanup on shell exit
    trap stop_services EXIT
  '';

  # Common project templates
  projectTemplates = {
    readme = projectName: ''
      # ${projectName}
      
      ## Quick Start
      
      ```bash
      # Start development
      ${lib.toLower projectName}-dev dev
      
      # Run tests
      ${lib.toLower projectName}-dev test
      
      # Build for production
      ${lib.toLower projectName}-dev build
      ```
      
      ## Development
      
      This project uses Nix for development environment management.
      
      ### Available Commands
      
      Run `${lib.toLower projectName}-dev` to see all available commands.
      
      ## License
      
      MIT
    '';
    
    dockerIgnore = ''
      .git
      .gitignore
      README.md
      Dockerfile
      .dockerignore
      node_modules
      npm-debug.log
      .nyc_output
      .coverage
      .coverage.*
      .cache
    '';
  };
}