# Template Component System
# Makes each template portable and composable as independent components

{ lib, pkgs, ... }:

let
  # Component interface definition
  mkComponent = {
    name,
    description,
    category,
    tags ? [],
    version ? "1.0.0",
    
    # Dependencies
    dependencies ? [],
    services ? [],
    ports ? {},
    
    # Environment configuration
    environment ? {},
    shellHook ? "",
    
    # Component lifecycle
    setup ? "",
    teardown ? "",
    healthCheck ? "",
    
    # Build inputs
    buildInputs ? [],
    
    # Component-specific configuration
    config ? {},
    
    # Composability
    provides ? [],      # What this component provides to others
    requires ? [],      # What this component requires from others
    conflicts ? [],     # Components that conflict with this one
  }: {
    inherit name description category tags version;
    inherit dependencies services ports environment;
    inherit setup teardown healthCheck;
    inherit buildInputs config;
    inherit provides requires conflicts;
    
    # Component metadata
    metadata = {
      inherit name description category tags version;
      created = builtins.currentTime;
      nixpkgs = lib.version;
    };
    
    # Full environment setup
    shell = pkgs.mkShell {
      inherit name buildInputs;
      
      shellHook = ''
        # Component identification
        export COMPONENT_NAME="${name}"
        export COMPONENT_VERSION="${version}"
        export COMPONENT_CATEGORY="${category}"
        
        # Set environment variables
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${toString v}\"") environment)}
        
        # Component-specific shell hook
        ${shellHook}
        
        # Health check function
        component_health() {
          echo "🔍 Health check for component: ${name}"
          ${healthCheck}
        }
        
        # Setup function
        component_setup() {
          echo "🚀 Setting up component: ${name}"
          ${setup}
        }
        
        # Teardown function
        component_teardown() {
          echo "🛑 Tearing down component: ${name}"
          ${teardown}
        }
        
        echo "📦 Component loaded: ${name} v${version}"
        echo "   Category: ${category}"
        echo "   Provides: ${lib.concatStringsSep ", " provides}"
        ${lib.optionalString (requires != []) "echo \"   Requires: ${lib.concatStringsSep ", " requires}\""}
      '';
    };
    
    # Component registry entry
    registryEntry = {
      inherit name description category tags version;
      inherit provides requires conflicts;
      path = toString ./.;
    };
  };

  # Pre-built component configurations
  componentConfigs = {
    # Web components
    nextjs-frontend = {
      name = "nextjs-frontend";
      description = "Next.js React frontend with TypeScript";
      category = "web-frontend";
      tags = [ "react" "nextjs" "typescript" "frontend" ];
      
      provides = [ "web-ui" "react-components" "frontend-routes" ];
      requires = [ "web-api" ];
      
      ports = { frontend = 3000; };
      environment = {
        NODE_ENV = "development";
        NEXT_TELEMETRY_DISABLED = "1";
      };
      
      buildInputs = with pkgs; [ nodejs_20 npm ];
      
      setup = ''
        if [ ! -f "package.json" ]; then
          npx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir --import-alias '@/*'
        fi
        npm install
      '';
      
      healthCheck = ''
        command -v node >/dev/null || { echo "❌ Node.js not found"; return 1; }
        command -v npm >/dev/null || { echo "❌ npm not found"; return 1; }
        [ -f "package.json" ] || { echo "❌ package.json not found"; return 1; }
        echo "✅ Next.js frontend component healthy"
      '';
    };

    node-api = {
      name = "node-api";
      description = "Node.js REST API with TypeScript and Prisma";
      category = "web-backend";
      tags = [ "nodejs" "typescript" "api" "rest" "prisma" ];
      
      provides = [ "web-api" "rest-endpoints" "database-access" ];
      requires = [ "postgresql" ];
      
      ports = { api = 8000; };
      services = [ "postgresql" ];
      environment = {
        NODE_ENV = "development";
        DATABASE_URL = "postgresql://postgres:password@localhost:5432/appdb";
      };
      
      buildInputs = with pkgs; [ nodejs_20 npm postgresql ];
      
      setup = ''
        if [ ! -f "package.json" ]; then
          npm init -y
          npm install express @types/express typescript ts-node prisma @prisma/client
          npm install -D nodemon @types/node
        fi
        
        if [ ! -f "prisma/schema.prisma" ]; then
          npx prisma init
        fi
      '';
      
      healthCheck = ''
        command -v node >/dev/null || { echo "❌ Node.js not found"; return 1; }
        command -v npx >/dev/null || { echo "❌ npx not found"; return 1; }
        pg_isready -h localhost -p 5432 >/dev/null || { echo "❌ PostgreSQL not running"; return 1; }
        echo "✅ Node.js API component healthy"
      '';
    };

    react-native-mobile = {
      name = "react-native-mobile";
      description = "React Native mobile app with Expo";
      category = "mobile";
      tags = [ "react-native" "expo" "mobile" "typescript" ];
      
      provides = [ "mobile-app" "mobile-ui" ];
      requires = [ "web-api" ];
      
      ports = { expo = 8081; metro = 8082; };
      environment = {
        EXPO_USE_FAST_RESOLVER = "1";
        REACT_NATIVE_PACKAGER_HOSTNAME = "localhost";
      };
      
      buildInputs = with pkgs; [ nodejs_20 npm watchman ];
      
      setup = ''
        if [ ! -f "package.json" ]; then
          npx create-expo-app@latest . --template blank-typescript
        fi
        npm install
      '';
      
      healthCheck = ''
        command -v node >/dev/null || { echo "❌ Node.js not found"; return 1; }
        command -v expo >/dev/null || { echo "❌ Expo CLI not found"; return 1; }
        command -v watchman >/dev/null || { echo "❌ Watchman not found"; return 1; }
        echo "✅ React Native component healthy"
      '';
    };

    python-ml = {
      name = "python-ml";
      description = "Python machine learning environment with Jupyter";
      category = "data-science";
      tags = [ "python" "ml" "jupyter" "pytorch" "tensorflow" ];
      
      provides = [ "ml-models" "data-analysis" "jupyter-notebooks" ];
      requires = [ ];
      
      ports = { jupyter = 8888; mlflow = 5000; };
      environment = {
        PYTHONPATH = "$PWD/src:$PYTHONPATH";
        JUPYTER_CONFIG_DIR = "$HOME/.jupyter";
      };
      
      buildInputs = with pkgs; [ 
        (python311.withPackages (ps: with ps; [
          jupyter jupyterlab numpy pandas scikit-learn
          matplotlib seaborn plotly torch tensorflow
        ]))
      ];
      
      setup = ''
        mkdir -p {notebooks,data,models,src}
        if [ ! -f "requirements.txt" ]; then
          cat > requirements.txt << EOF
    jupyter
    pandas
    numpy
    scikit-learn
    matplotlib
    seaborn
    torch
    tensorflow
    EOF
        fi
      '';
      
      healthCheck = ''
        command -v python >/dev/null || { echo "❌ Python not found"; return 1; }
        command -v jupyter >/dev/null || { echo "❌ Jupyter not found"; return 1; }
        python -c "import torch, tensorflow" 2>/dev/null || { echo "❌ ML libraries not available"; return 1; }
        echo "✅ Python ML component healthy"
      '';
    };

    postgresql-db = {
      name = "postgresql-db";
      description = "PostgreSQL database service";
      category = "database";
      tags = [ "postgresql" "database" "sql" ];
      
      provides = [ "postgresql" "sql-database" ];
      requires = [ ];
      
      ports = { postgresql = 5432; };
      services = [ "postgresql" ];
      environment = {
        PGDATA = "$PWD/.postgres";
        PGHOST = "localhost";
        PGPORT = "5432";
        PGUSER = "postgres";
        DATABASE_URL = "postgresql://postgres:password@localhost:5432/appdb";
      };
      
      buildInputs = with pkgs; [ postgresql ];
      
      setup = ''
        if [ ! -d "$PGDATA" ]; then
          initdb "$PGDATA" --auth-host=trust --auth-local=trust
          echo "port = 5432" >> "$PGDATA/postgresql.conf"
        fi
        
        if ! pg_ctl status >/dev/null 2>&1; then
          pg_ctl start -l "$PGDATA/server.log"
        fi
        
        # Create default database
        createdb appdb 2>/dev/null || true
      '';
      
      teardown = ''
        if pg_ctl status >/dev/null 2>&1; then
          pg_ctl stop
        fi
      '';
      
      healthCheck = ''
        command -v pg_ctl >/dev/null || { echo "❌ PostgreSQL not found"; return 1; }
        pg_isready -h localhost -p 5432 >/dev/null || { echo "❌ PostgreSQL not running"; return 1; }
        echo "✅ PostgreSQL component healthy"
      '';
    };

    redis-cache = {
      name = "redis-cache";
      description = "Redis caching service";
      category = "cache";
      tags = [ "redis" "cache" "memory" ];
      
      provides = [ "redis" "cache" "session-store" ];
      requires = [ ];
      
      ports = { redis = 6379; };
      services = [ "redis" ];
      environment = {
        REDIS_URL = "redis://localhost:6379";
      };
      
      buildInputs = with pkgs; [ redis ];
      
      setup = ''
        if ! redis-cli ping >/dev/null 2>&1; then
          redis-server --daemonize yes --port 6379
        fi
      '';
      
      teardown = ''
        if redis-cli ping >/dev/null 2>&1; then
          redis-cli shutdown
        fi
      '';
      
      healthCheck = ''
        command -v redis-server >/dev/null || { echo "❌ Redis not found"; return 1; }
        redis-cli ping >/dev/null || { echo "❌ Redis not running"; return 1; }
        echo "✅ Redis component healthy"
      '';
    };
  };

  # Component composition functions
  composeComponents = components: 
    let
      allComponents = map (name: componentConfigs.${name}) components;
      
      # Check for conflicts
      checkConflicts = comps:
        let
          conflicts = lib.flatten (map (c: c.conflicts or []) comps);
          componentNames = map (c: c.name) comps;
          foundConflicts = lib.intersectLists conflicts componentNames;
        in
        if foundConflicts != []
        then throw "Component conflicts detected: ${lib.concatStringsSep ", " foundConflicts}"
        else comps;
      
      # Resolve dependencies
      resolveDependencies = comps:
        let
          required = lib.unique (lib.flatten (map (c: c.requires or []) comps));
          provided = lib.unique (lib.flatten (map (c: c.provides or []) comps));
          missing = lib.subtractLists provided required;
        in
        if missing != []
        then throw "Missing required dependencies: ${lib.concatStringsSep ", " missing}"
        else comps;
      
      validatedComponents = resolveDependencies (checkConflicts allComponents);
      
      # Merge configurations
      mergedBuildInputs = lib.unique (lib.flatten (map (c: c.buildInputs or []) validatedComponents));
      mergedPorts = lib.foldr (c: acc: acc // (c.ports or {})) {} validatedComponents;
      mergedEnvironment = lib.foldr (c: acc: acc // (c.environment or {})) {} validatedComponents;
      mergedServices = lib.unique (lib.flatten (map (c: c.services or []) validatedComponents));
      
    in {
      inherit validatedComponents mergedBuildInputs mergedPorts mergedEnvironment mergedServices;
      
      # Combined shell environment
      shell = pkgs.mkShell {
        name = "composed-components";
        buildInputs = mergedBuildInputs;
        
        shellHook = ''
          echo "🏗️ Composed Development Environment"
          echo "Components: ${lib.concatStringsSep ", " (map (c: c.name) validatedComponents)}"
          echo "Services: ${lib.concatStringsSep ", " mergedServices}"
          echo "Ports: ${lib.concatStringsSep ", " (lib.mapAttrsToList (k: v: "${k}:${toString v}") mergedPorts)}"
          
          # Set all environment variables
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${toString v}\"") mergedEnvironment)}
          
          # Component setup functions
          setup_all() {
            echo "🚀 Setting up all components..."
            ${lib.concatStringsSep "\n" (map (c: c.setup or "") validatedComponents)}
            echo "✅ All components set up"
          }
          
          teardown_all() {
            echo "🛑 Tearing down all components..."
            ${lib.concatStringsSep "\n" (map (c: c.teardown or "") validatedComponents)}
            echo "✅ All components torn down"
          }
          
          health_all() {
            echo "🔍 Checking health of all components..."
            ${lib.concatStringsSep "\n" (map (c: c.healthCheck or "echo \"No health check for ${c.name}\"") validatedComponents)}
          }
          
          # Auto-setup on entry
          setup_all
        '';
      };
    };

  # Component registry and discovery
  componentRegistry = pkgs.writeShellScriptBin "component" ''
    case "$1" in
      list)
        echo "📦 Available Components"
        echo "════════════════════════════════════════════════════════════════════════════════"
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: config: ''
        echo "📦 ${config.name}"
        echo "   Description: ${config.description}"
        echo "   Category: ${config.category}"
        echo "   Provides: ${lib.concatStringsSep ", " config.provides}"
        echo "   Requires: ${lib.concatStringsSep ", " config.requires}"
        echo ""
        '') componentConfigs)}
        ;;
      
      compose)
        shift
        if [ $# -eq 0 ]; then
          echo "Usage: component compose <component1> <component2> ..."
          echo ""
          echo "Available components:"
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: "echo \"  ${name}\"") componentConfigs)}
          exit 1
        fi
        
        echo "🏗️ Composing components: $*"
        echo "This would create a composed environment with:"
        for comp in "$@"; do
          echo "  - $comp"
        done
        echo ""
        echo "💡 Use 'nix develop' with the composed configuration"
        ;;
      
      info)
        if [ -z "$2" ]; then
          echo "Usage: component info <component-name>"
          exit 1
        fi
        
        case "$2" in
          ${lib.concatStringsSep "\n          " (lib.mapAttrsToList (name: config: ''
          ${name})
            echo "📦 ${config.name}"
            echo "Description: ${config.description}"
            echo "Category: ${config.category}"
            echo "Tags: ${lib.concatStringsSep ", " config.tags}"
            echo "Provides: ${lib.concatStringsSep ", " config.provides}"
            echo "Requires: ${lib.concatStringsSep ", " config.requires}"
            echo "Ports: ${lib.concatStringsSep ", " (lib.mapAttrsToList (k: v: "${k}:${toString v}") config.ports)}"
            ;;'') componentConfigs)}
          *)
            echo "❌ Unknown component: $2"
            echo "Run 'component list' to see available components"
            ;;
        esac
        ;;
      
      *)
        echo "📦 Component Management System"
        echo ""
        echo "Usage: component <command> [args]"
        echo ""
        echo "Commands:"
        echo "  list              List all available components"
        echo "  info <name>       Show detailed component information"
        echo "  compose <names>   Compose multiple components"
        echo ""
        echo "Examples:"
        echo "  component list"
        echo "  component info nextjs-frontend"
        echo "  component compose nextjs-frontend node-api postgresql-db"
        ;;
    esac
  '';

in {
  inherit mkComponent componentConfigs composeComponents;
  
  # Export component registry
  registry = componentRegistry;
  
  # Quick composition helpers
  webStack = composeComponents [ "nextjs-frontend" "node-api" "postgresql-db" "redis-cache" ];
  mobileStack = composeComponents [ "react-native-mobile" "node-api" "postgresql-db" ];
  mlStack = composeComponents [ "python-ml" "postgresql-db" ];
  
  # Individual components as shells
  components = lib.mapAttrs (name: config: (mkComponent config).shell) componentConfigs;
}