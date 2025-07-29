#!/usr/bin/env bash

# Component Development Script
# Manages portable and composable development components

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
COMPONENTS_DIR="${COMPONENTS_DIR:-$HOME/.local/share/components}"
TEMPLATES_DIR="${TEMPLATES_DIR:-$HOME/dotfiles/templates}"
COMPONENT_REGISTRY="$COMPONENTS_DIR/registry.json"

# Initialize component system
init_component_system() {
    mkdir -p "$COMPONENTS_DIR"/{instances,compositions,cache}
    
    # Create component registry if it doesn't exist
    if [ ! -f "$COMPONENT_REGISTRY" ]; then
        cat > "$COMPONENT_REGISTRY" << 'EOF'
{
  "version": "1.0.0",
  "components": {},
  "compositions": {},
  "instances": {}
}
EOF
    fi
}

# Component management functions
create_component() {
    local component_type="$1"
    local instance_name="$2"
    local target_dir="$3"
    
    if [ -z "$component_type" ] || [ -z "$instance_name" ] || [ -z "$target_dir" ]; then
        echo -e "${RED}Usage: component-dev create <type> <name> <directory>${NC}"
        echo -e "${YELLOW}Available types: frontend, backend, mobile, database, cache, ml${NC}"
        return 1
    fi
    
    echo -e "${GREEN}🏗️ Creating component: $instance_name ($component_type)${NC}"
    
    # Create instance directory
    mkdir -p "$target_dir"
    cd "$target_dir"
    
    # Create component descriptor
    cat > component.json << EOF
{
  "name": "$instance_name",
  "type": "$component_type",
  "version": "1.0.0",
  "created": "$(date -Iseconds)",
  "directory": "$target_dir",
  "status": "created",
  "dependencies": [],
  "provides": [],
  "requires": [],
  "ports": {},
  "environment": {}
}
EOF
    
    # Type-specific initialization
    case "$component_type" in
        frontend)
            echo -e "${BLUE}🎨 Initializing frontend component...${NC}"
            cat >> component.json << 'EOF'
{
  "provides": ["web-ui", "frontend-routes"],
  "requires": ["web-api"],
  "ports": {"frontend": 3000},
  "environment": {
    "NODE_ENV": "development",
    "NEXT_TELEMETRY_DISABLED": "1"
  }
}
EOF
            # Initialize Next.js project
            nix develop "$TEMPLATES_DIR/web/nextjs-fullstack" --command bash -c "
                setup-nextjs
                echo '✅ Frontend component initialized'
            "
            ;;
            
        backend)
            echo -e "${BLUE}⚙️ Initializing backend component...${NC}"
            cat >> component.json << 'EOF'
{
  "provides": ["web-api", "rest-endpoints"],
  "requires": ["database"],
  "ports": {"api": 8000},
  "environment": {
    "NODE_ENV": "development",
    "DATABASE_URL": "postgresql://postgres:password@localhost:5432/appdb"
  }
}
EOF
            # Initialize Node.js API
            nix develop "$TEMPLATES_DIR/web/node-api" --command bash -c "
                setup-node-api
                api-dev init
                echo '✅ Backend component initialized'
            "
            ;;
            
        mobile)
            echo -e "${BLUE}📱 Initializing mobile component...${NC}"
            cat >> component.json << 'EOF'
{
  "provides": ["mobile-app"],
  "requires": ["web-api"],
  "ports": {"expo": 8081},
  "environment": {
    "EXPO_USE_FAST_RESOLVER": "1"
  }
}
EOF
            # Initialize React Native
            nix develop "$TEMPLATES_DIR/mobile/react-native" --command bash -c "
                setup-react-native
                rn-dev create $instance_name
                echo '✅ Mobile component initialized'
            "
            ;;
            
        database)
            echo -e "${BLUE}🗄️ Initializing database component...${NC}"
            cat >> component.json << 'EOF'
{
  "provides": ["database", "postgresql"],
  "requires": [],
  "ports": {"postgresql": 5432},
  "environment": {
    "PGDATA": "./.postgres",
    "DATABASE_URL": "postgresql://postgres:password@localhost:5432/appdb"
  }
}
EOF
            # Initialize PostgreSQL
            export PGDATA="$PWD/.postgres"
            if [ ! -d "$PGDATA" ]; then
                initdb "$PGDATA" --auth-host=trust --auth-local=trust
                echo "port = 5432" >> "$PGDATA/postgresql.conf"
            fi
            echo '✅ Database component initialized'
            ;;
            
        cache)
            echo -e "${BLUE}🔴 Initializing cache component...${NC}"
            cat >> component.json << 'EOF'
{
  "provides": ["cache", "redis"],
  "requires": [],
  "ports": {"redis": 6379},
  "environment": {
    "REDIS_URL": "redis://localhost:6379"
  }
}
EOF
            echo '✅ Cache component initialized'
            ;;
            
        ml)
            echo -e "${BLUE}🧬 Initializing ML component...${NC}"
            cat >> component.json << 'EOF'
{
  "provides": ["ml-models", "jupyter"],
  "requires": [],
  "ports": {"jupyter": 8888, "mlflow": 5000},
  "environment": {
    "PYTHONPATH": "./src:$PYTHONPATH"
  }
}
EOF
            # Initialize ML environment
            nix develop "$TEMPLATES_DIR/data/python-ml" --command bash -c "
                setup-datascience
                echo '✅ ML component initialized'
            "
            ;;
            
        *)
            echo -e "${RED}❌ Unknown component type: $component_type${NC}"
            return 1
            ;;
    esac
    
    # Register component
    jq ".components[\"$instance_name\"] = {
        \"name\": \"$instance_name\",
        \"type\": \"$component_type\",
        \"directory\": \"$target_dir\",
        \"created\": \"$(date -Iseconds)\"
    }" "$COMPONENT_REGISTRY" > "$COMPONENT_REGISTRY.tmp" && mv "$COMPONENT_REGISTRY.tmp" "$COMPONENT_REGISTRY"
    
    echo -e "${GREEN}✅ Component created: $instance_name${NC}"
    echo -e "${CYAN}📁 Location: $target_dir${NC}"
    echo -e "${CYAN}💡 Use 'component-dev start $instance_name' to run${NC}"
}

# Start component in development mode
start_component() {
    local instance_name="$1"
    
    if [ ! -f "component.json" ]; then
        echo -e "${RED}❌ No component.json found in current directory${NC}"
        echo -e "${YELLOW}💡 Run 'component-dev create' to create a component${NC}"
        return 1
    fi
    
    local component_type=$(jq -r '.type' component.json)
    local component_name=$(jq -r '.name' component.json)
    
    echo -e "${GREEN}🚀 Starting component: $component_name ($component_type)${NC}"
    
    # Start dependencies first
    start_dependencies
    
    # Component-specific startup
    case "$component_type" in
        frontend)
            echo -e "${BLUE}🎨 Starting frontend development server...${NC}"
            nix develop "$TEMPLATES_DIR/web/nextjs-fullstack" --command bash -c "
                if [ -d '$component_name-frontend' ]; then
                    cd $component_name-frontend
                fi
                nextjs-dev dev
            "
            ;;
            
        backend)
            echo -e "${BLUE}⚙️ Starting backend API server...${NC}"
            nix develop "$TEMPLATES_DIR/web/node-api" --command bash -c "
                api-dev dev
            "
            ;;
            
        mobile)
            echo -e "${BLUE}📱 Starting mobile development...${NC}"
            nix develop "$TEMPLATES_DIR/mobile/react-native" --command bash -c "
                if [ -d '$component_name' ]; then
                    cd $component_name
                fi
                rn-dev run
            "
            ;;
            
        database)
            echo -e "${BLUE}🗄️ Starting database service...${NC}"
            export PGDATA="$PWD/.postgres"
            if ! pg_ctl status >/dev/null 2>&1; then
                pg_ctl start -l "$PGDATA/server.log"
                echo -e "${GREEN}✅ PostgreSQL started${NC}"
            else
                echo -e "${CYAN}ℹ️ PostgreSQL already running${NC}"
            fi
            ;;
            
        cache)
            echo -e "${BLUE}🔴 Starting cache service...${NC}"
            if ! redis-cli ping >/dev/null 2>&1; then
                redis-server --daemonize yes --port 6379
                echo -e "${GREEN}✅ Redis started${NC}"
            else
                echo -e "${CYAN}ℹ️ Redis already running${NC}"
            fi
            ;;
            
        ml)
            echo -e "${BLUE}🧬 Starting ML development environment...${NC}"
            nix develop "$TEMPLATES_DIR/data/python-ml" --command bash -c "
                ds-dev notebook
            "
            ;;
    esac
}

# Start component dependencies
start_dependencies() {
    if [ ! -f "component.json" ]; then
        return 0
    fi
    
    local requires=$(jq -r '.requires[]?' component.json)
    
    for dep in $requires; do
        case "$dep" in
            database|postgresql)
                if ! pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
                    echo -e "${YELLOW}🗄️ Starting required database service...${NC}"
                    export PGDATA="$PWD/.postgres"
                    if [ ! -d "$PGDATA" ]; then
                        initdb "$PGDATA" --auth-host=trust --auth-local=trust
                        echo "port = 5432" >> "$PGDATA/postgresql.conf"
                    fi
                    pg_ctl start -l "$PGDATA/server.log"
                fi
                ;;
            cache|redis)
                if ! redis-cli ping >/dev/null 2>&1; then
                    echo -e "${YELLOW}🔴 Starting required cache service...${NC}"
                    redis-server --daemonize yes --port 6379
                fi
                ;;
        esac
    done
}

# Stop component and its services
stop_component() {
    if [ ! -f "component.json" ]; then
        echo -e "${RED}❌ No component.json found${NC}"
        return 1
    fi
    
    local component_type=$(jq -r '.type' component.json)
    local component_name=$(jq -r '.name' component.json)
    
    echo -e "${YELLOW}🛑 Stopping component: $component_name ($component_type)${NC}"
    
    # Stop component-specific services
    case "$component_type" in
        database)
            export PGDATA="$PWD/.postgres"
            if pg_ctl status >/dev/null 2>&1; then
                pg_ctl stop
                echo -e "${GREEN}✅ PostgreSQL stopped${NC}"
            fi
            ;;
        cache)
            if redis-cli ping >/dev/null 2>&1; then
                redis-cli shutdown
                echo -e "${GREEN}✅ Redis stopped${NC}"
            fi
            ;;
    esac
}

# Component status
component_status() {
    if [ ! -f "component.json" ]; then
        echo -e "${RED}❌ No component found in current directory${NC}"
        return 1
    fi
    
    local component_name=$(jq -r '.name' component.json)
    local component_type=$(jq -r '.type' component.json)
    local provides=$(jq -r '.provides[]?' component.json)
    local requires=$(jq -r '.requires[]?' component.json)
    
    echo -e "${CYAN}📦 Component Status: $component_name ($component_type)${NC}"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    echo -e "${BLUE}Provides:${NC} ${provides:-none}"
    echo -e "${BLUE}Requires:${NC} ${requires:-none}"
    
    # Check service status
    echo -e "\n${CYAN}🔧 Services:${NC}"
    
    if echo "$provides" | grep -q "database\|postgresql"; then
        if pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅ PostgreSQL${NC} (port 5432)"
        else
            echo -e "  ${RED}❌ PostgreSQL${NC} (stopped)"
        fi
    fi
    
    if echo "$provides" | grep -q "cache\|redis"; then
        if redis-cli ping >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅ Redis${NC} (port 6379)"
        else
            echo -e "  ${RED}❌ Redis${NC} (stopped)"
        fi
    fi
    
    # Check ports
    local ports=$(jq -r '.ports | to_entries[]? | "\(.key):\(.value)"' component.json)
    if [ -n "$ports" ]; then
        echo -e "\n${CYAN}🌐 Ports:${NC}"
        echo "$ports" | while IFS=: read -r name port; do
            if nc -z localhost "$port" 2>/dev/null; then
                echo -e "  ${GREEN}✅ $name${NC} (port $port)"
            else
                echo -e "  ${BLUE}⚪ $name${NC} (port $port - available)"
            fi
        done
    fi
}

# List all components
list_components() {
    echo -e "${CYAN}📦 Available Component Types:${NC}"
    echo "────────────────────────────────────────────────────────────────────────────────"
    echo -e "${GREEN}frontend${NC}   - Next.js React frontend with TypeScript"
    echo -e "${GREEN}backend${NC}    - Node.js REST API with TypeScript and Prisma"
    echo -e "${GREEN}mobile${NC}     - React Native mobile app with Expo"
    echo -e "${GREEN}database${NC}   - PostgreSQL database service"
    echo -e "${GREEN}cache${NC}      - Redis caching service"
    echo -e "${GREEN}ml${NC}         - Python machine learning environment"
    
    if [ -f "$COMPONENT_REGISTRY" ]; then
        echo -e "\n${CYAN}📋 Created Components:${NC}"
        jq -r '.components | to_entries[]? | "  \(.value.name) (\(.value.type)) - \(.value.directory)"' "$COMPONENT_REGISTRY"
    fi
}

# Compose multiple components
compose_components() {
    local composition_name="$1"
    shift
    local components=("$@")
    
    if [ ${#components[@]} -eq 0 ]; then
        echo -e "${RED}Usage: component-dev compose <name> <component1> <component2> ...${NC}"
        return 1
    fi
    
    echo -e "${GREEN}🏗️ Creating composition: $composition_name${NC}"
    echo -e "${BLUE}Components: ${components[*]}${NC}"
    
    local composition_dir="$COMPONENTS_DIR/compositions/$composition_name"
    mkdir -p "$composition_dir"
    
    # Create composition descriptor
    cat > "$composition_dir/composition.json" << EOF
{
  "name": "$composition_name",
  "components": [$(printf '"%s",' "${components[@]}" | sed 's/,$//')]," 
  "created": "$(date -Iseconds)",
  "status": "created"
}
EOF
    
    # Create composition startup script
    cat > "$composition_dir/start.sh" << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting composition: $(jq -r '.name' composition.json)"
echo "Components: $(jq -r '.components | join(", ")' composition.json)"

# Start each component
jq -r '.components[]' composition.json | while read -r component; do
    echo "Starting component: $component"
    # Component startup logic would go here
done
EOF
    
    chmod +x "$composition_dir/start.sh"
    
    echo -e "${GREEN}✅ Composition created: $composition_dir${NC}"
}

# Main command dispatcher
main() {
    init_component_system
    
    case "$1" in
        create)
            create_component "$2" "$3" "$4"
            ;;
        start)
            start_component "$2"
            ;;
        stop)
            stop_component
            ;;
        status)
            component_status
            ;;
        list)
            list_components
            ;;
        compose)
            shift
            compose_components "$@"
            ;;
        enter)
            if [ ! -f "component.json" ]; then
                echo -e "${RED}❌ No component found${NC}"
                exit 1
            fi
            
            component_type=$(jq -r '.type' component.json)
            case "$component_type" in
                frontend)
                    nix develop "$TEMPLATES_DIR/web/nextjs-fullstack"
                    ;;
                backend)
                    nix develop "$TEMPLATES_DIR/web/node-api"
                    ;;
                mobile)
                    nix develop "$TEMPLATES_DIR/mobile/react-native"
                    ;;
                ml)
                    nix develop "$TEMPLATES_DIR/data/python-ml"
                    ;;
                *)
                    echo -e "${YELLOW}💡 No specific environment for $component_type${NC}"
                    ;;
            esac
            ;;
        *)
            echo -e "${BLUE}📦 Component Development Manager${NC}"
            echo ""
            echo -e "${YELLOW}Usage: component-dev <command> [args]${NC}"
            echo ""
            echo -e "${CYAN}Component Management:${NC}"
            echo "  create <type> <name> <dir>  Create new component"
            echo "  start [name]               Start component in dev mode"
            echo "  stop                       Stop component services"
            echo "  status                     Show component status"
            echo "  enter                      Enter component environment"
            echo ""
            echo -e "${CYAN}Discovery:${NC}"
            echo "  list                       List available component types"
            echo ""
            echo -e "${CYAN}Composition:${NC}"
            echo "  compose <name> <comps...>  Compose multiple components"
            echo ""
            echo -e "${CYAN}Examples:${NC}"
            echo "  component-dev create frontend my-app ./frontend"
            echo "  component-dev create backend api-server ./backend"
            echo "  component-dev start"
            echo "  component-dev compose fullstack frontend backend database"
            ;;
    esac
}

main "$@"