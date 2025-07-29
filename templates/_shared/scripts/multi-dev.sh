#!/usr/bin/env bash

# Multi-Development Environment Script
# Simplifies working with multiple templates simultaneously

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
TEMPLATES_DIR="${TEMPLATES_DIR:-$HOME/dotfiles/templates}"
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/.local/share/workspaces}"
SESSION_FILE="$WORKSPACE_DIR/.active_sessions"

# Helper functions
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🏗️ Multi-Development Environment Manager${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo -e "\n${CYAN}$1${NC}"
    echo "────────────────────────────────────────────────────────────────────────────────"
}

# Quick combinations
quick_fullstack() {
    local project_name="$1"
    echo -e "${GREEN}🚀 Setting up fullstack project: $project_name${NC}"
    
    mkdir -p "$project_name"/{frontend,backend}
    cd "$project_name"
    
    # Create project descriptor
    cat > project.json << EOF
{
  "name": "$project_name",
  "type": "fullstack-web",
  "components": {
    "frontend": {
      "template": "web/nextjs-fullstack",
      "port": 3000,
      "dir": "frontend"
    },
    "backend": {
      "template": "web/node-api", 
      "port": 8000,
      "dir": "backend"
    }
  },
  "services": ["postgresql", "redis"],
  "created": "$(date -Iseconds)"
}
EOF
    
    # Setup frontend
    echo -e "${YELLOW}📦 Setting up frontend (Next.js)...${NC}"
    cd frontend
    nix develop "$TEMPLATES_DIR/web/nextjs-fullstack" --command bash -c "
        setup-nextjs
        nextjs-dev create $project_name-frontend
        echo '✅ Frontend initialized'
    "
    cd ..
    
    # Setup backend
    echo -e "${YELLOW}🔧 Setting up backend (Node.js API)...${NC}"
    cd backend
    nix develop "$TEMPLATES_DIR/web/node-api" --command bash -c "
        setup-node-api
        api-dev init
        echo '✅ Backend initialized'
    "
    cd ..
    
    echo -e "${GREEN}✅ Fullstack project ready!${NC}"
    echo -e "${BLUE}Next steps:${NC}"
    echo "  cd $project_name"
    echo "  multi-dev start"
}

quick_mobile_backend() {
    local project_name="$1"
    echo -e "${GREEN}📱 Setting up mobile + backend project: $project_name${NC}"
    
    mkdir -p "$project_name"/{mobile,backend}
    cd "$project_name"
    
    cat > project.json << EOF
{
  "name": "$project_name",
  "type": "mobile-backend",
  "components": {
    "mobile": {
      "template": "mobile/react-native",
      "port": 8081,
      "dir": "mobile"
    },
    "backend": {
      "template": "web/node-api",
      "port": 8000,
      "dir": "backend"
    }
  },
  "services": ["postgresql", "redis"],
  "created": "$(date -Iseconds)"
}
EOF
    
    # Setup mobile
    echo -e "${YELLOW}📱 Setting up mobile (React Native)...${NC}"
    cd mobile
    nix develop "$TEMPLATES_DIR/mobile/react-native" --command bash -c "
        setup-react-native
        rn-dev create $project_name-mobile
        echo '✅ Mobile app initialized'
    "
    cd ..
    
    # Setup backend
    echo -e "${YELLOW}🔧 Setting up backend...${NC}"
    cd backend
    nix develop "$TEMPLATES_DIR/web/node-api" --command bash -c "
        setup-node-api
        api-dev init
        echo '✅ Backend initialized'
    "
    cd ..
    
    echo -e "${GREEN}✅ Mobile + Backend project ready!${NC}"
}

quick_ml_platform() {
    local project_name="$1"
    echo -e "${GREEN}🧬 Setting up ML platform: $project_name${NC}"
    
    mkdir -p "$project_name"/{ml-models,dashboard,api}
    cd "$project_name"
    
    cat > project.json << EOF
{
  "name": "$project_name", 
  "type": "ml-platform",
  "components": {
    "ml": {
      "template": "data/python-ml",
      "port": 8888,
      "dir": "ml-models"
    },
    "dashboard": {
      "template": "web/nextjs-fullstack",
      "port": 3000,
      "dir": "dashboard"
    },
    "api": {
      "template": "web/node-api",
      "port": 8000,
      "dir": "api"
    }
  },
  "services": ["postgresql", "redis", "jupyter", "mlflow"],
  "created": "$(date -Iseconds)"
}
EOF
    
    # Setup each component
    echo -e "${YELLOW}🧬 Setting up ML environment...${NC}"
    cd ml-models
    nix develop "$TEMPLATES_DIR/data/python-ml" --command bash -c "
        setup-datascience
        echo '✅ ML environment initialized'
    "
    cd ..
    
    echo -e "${YELLOW}📊 Setting up dashboard...${NC}"
    cd dashboard  
    nix develop "$TEMPLATES_DIR/web/nextjs-fullstack" --command bash -c "
        setup-nextjs
        nextjs-dev create $project_name-dashboard
        echo '✅ Dashboard initialized'
    "
    cd ..
    
    echo -e "${YELLOW}🔧 Setting up API...${NC}"
    cd api
    nix develop "$TEMPLATES_DIR/web/node-api" --command bash -c "
        setup-node-api
        api-dev init
        echo '✅ API initialized'
    "
    cd ..
    
    echo -e "${GREEN}✅ ML Platform ready!${NC}"
}

# Service management
start_services() {
    echo -e "${GREEN}🚀 Starting development services...${NC}"
    
    # PostgreSQL
    export PGDATA="$PWD/.postgres"
    if [ ! -d "$PGDATA" ]; then
        echo -e "${YELLOW}🗄️ Initializing PostgreSQL...${NC}"
        initdb "$PGDATA" --auth-host=trust --auth-local=trust
        echo "port = 5432" >> "$PGDATA/postgresql.conf"
    fi
    
    if ! pg_ctl status > /dev/null 2>&1; then
        pg_ctl start -l "$PGDATA/server.log"
        echo -e "${GREEN}✅ PostgreSQL started (port 5432)${NC}"
    else
        echo -e "${BLUE}ℹ️ PostgreSQL already running${NC}"
    fi
    
    # Redis
    if ! redis-cli ping > /dev/null 2>&1; then
        redis-server --daemonize yes --port 6379 --logfile redis.log
        echo -e "${GREEN}✅ Redis started (port 6379)${NC}"
    else
        echo -e "${BLUE}ℹ️ Redis already running${NC}"
    fi
}

stop_services() {
    echo -e "${YELLOW}🛑 Stopping development services...${NC}"
    
    # Stop PostgreSQL
    export PGDATA="$PWD/.postgres"
    if pg_ctl status > /dev/null 2>&1; then
        pg_ctl stop
        echo -e "${GREEN}✅ PostgreSQL stopped${NC}"
    fi
    
    # Stop Redis
    if redis-cli ping > /dev/null 2>&1; then
        redis-cli shutdown
        echo -e "${GREEN}✅ Redis stopped${NC}"
    fi
}

# Development session management
start_dev_session() {
    if [ ! -f "project.json" ]; then
        echo -e "${RED}❌ No project.json found. Create a project first.${NC}"
        exit 1
    fi
    
    project_name=$(jq -r '.name' project.json)
    project_type=$(jq -r '.type' project.json)
    
    echo -e "${GREEN}🚀 Starting development session: $project_name ($project_type)${NC}"
    
    # Start services
    start_services
    
    # Open development terminals based on project type
    case "$project_type" in
        fullstack-web)
            echo -e "${BLUE}📂 Opening frontend and backend terminals...${NC}"
            # Frontend terminal
            if command -v osascript &> /dev/null; then
                osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/frontend' && nix develop $TEMPLATES_DIR/web/nextjs-fullstack\""
                osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/backend' && nix develop $TEMPLATES_DIR/web/node-api\""
            elif command -v gnome-terminal &> /dev/null; then
                gnome-terminal --tab --title="Frontend" --working-directory="$PWD/frontend" -- bash -c "nix develop $TEMPLATES_DIR/web/nextjs-fullstack; exec bash"
                gnome-terminal --tab --title="Backend" --working-directory="$PWD/backend" -- bash -c "nix develop $TEMPLATES_DIR/web/node-api; exec bash"
            else
                echo -e "${YELLOW}⚠️ Auto terminal opening not supported. Manually run:${NC}"
                echo "  Terminal 1: cd frontend && nix develop $TEMPLATES_DIR/web/nextjs-fullstack"
                echo "  Terminal 2: cd backend && nix develop $TEMPLATES_DIR/web/node-api"
            fi
            ;;
        mobile-backend)
            echo -e "${BLUE}📱 Opening mobile and backend terminals...${NC}"
            if command -v osascript &> /dev/null; then
                osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/mobile' && nix develop $TEMPLATES_DIR/mobile/react-native\""
                osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/backend' && nix develop $TEMPLATES_DIR/web/node-api\""
            else
                echo -e "${YELLOW}⚠️ Auto terminal opening not supported. Manually run:${NC}"
                echo "  Terminal 1: cd mobile && nix develop $TEMPLATES_DIR/mobile/react-native"
                echo "  Terminal 2: cd backend && nix develop $TEMPLATES_DIR/web/node-api"
            fi
            ;;
        ml-platform)
            echo -e "${BLUE}🧬 Opening ML platform terminals...${NC}"
            if command -v osascript &> /dev/null; then
                osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/ml-models' && nix develop $TEMPLATES_DIR/data/python-ml\""
                osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/dashboard' && nix develop $TEMPLATES_DIR/web/nextjs-fullstack\""
                osascript -e "tell application \"Terminal\" to do script \"cd '$PWD/api' && nix develop $TEMPLATES_DIR/web/node-api\""
            else
                echo -e "${YELLOW}⚠️ Auto terminal opening not supported. Manually run:${NC}"
                echo "  Terminal 1: cd ml-models && nix develop $TEMPLATES_DIR/data/python-ml"
                echo "  Terminal 2: cd dashboard && nix develop $TEMPLATES_DIR/web/nextjs-fullstack"
                echo "  Terminal 3: cd api && nix develop $TEMPLATES_DIR/web/node-api"
            fi
            ;;
    esac
    
    # Save session info
    mkdir -p "$WORKSPACE_DIR"
    echo "$PWD" >> "$SESSION_FILE"
    
    echo -e "${GREEN}✅ Development session started!${NC}"
    show_status
}

# Status display
show_status() {
    if [ ! -f "project.json" ]; then
        echo -e "${RED}❌ No project found in current directory${NC}"
        return
    fi
    
    project_name=$(jq -r '.name' project.json)
    project_type=$(jq -r '.type' project.json)
    
    print_section "📊 Project Status: $project_name ($project_type)"
    
    # Service status
    echo -e "${CYAN}🔧 Services:${NC}"
    if pg_ctl status > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ PostgreSQL${NC} (port 5432)"
    else
        echo -e "  ${RED}❌ PostgreSQL${NC} (stopped)"
    fi
    
    if redis-cli ping > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Redis${NC} (port 6379)"
    else
        echo -e "  ${RED}❌ Redis${NC} (stopped)"
    fi
    
    # Port status
    echo -e "\n${CYAN}🌐 Development Ports:${NC}"
    for port in 3000 8000 8080 8081 8888 5000; do
        if nc -z localhost $port 2>/dev/null; then
            echo -e "  ${GREEN}✅ Port $port${NC} (in use)"
        else
            echo -e "  ${BLUE}⚪ Port $port${NC} (available)"
        fi
    done
    
    # Component status
    echo -e "\n${CYAN}📁 Components:${NC}"
    jq -r '.components | to_entries[] | "  \(.key): \(.value.template) (port \(.value.port))"' project.json
}

# Main function
main() {
    case "$1" in
        quick)
            case "$2" in
                fullstack)
                    if [ -z "$3" ]; then
                        echo "Usage: multi-dev quick fullstack <project-name>"
                        exit 1
                    fi
                    quick_fullstack "$3"
                    ;;
                mobile)
                    if [ -z "$3" ]; then
                        echo "Usage: multi-dev quick mobile <project-name>"
                        exit 1
                    fi
                    quick_mobile_backend "$3"
                    ;;
                ml)
                    if [ -z "$3" ]; then
                        echo "Usage: multi-dev quick ml <project-name>"
                        exit 1
                    fi
                    quick_ml_platform "$3"
                    ;;
                *)
                    echo "Available quick setups: fullstack, mobile, ml"
                    ;;
            esac
            ;;
        start)
            start_dev_session
            ;;
        stop)
            stop_services
            ;;
        status)
            show_status
            ;;
        services)
            case "$2" in
                start)
                    start_services
                    ;;
                stop)
                    stop_services
                    ;;
                restart)
                    stop_services
                    sleep 2
                    start_services
                    ;;
                *)
                    echo "Usage: multi-dev services {start|stop|restart}"
                    ;;
            esac
            ;;
        *)
            print_header
            echo -e "\n${CYAN}Usage: multi-dev <command> [args]${NC}"
            echo ""
            echo -e "${YELLOW}Quick Setup Commands:${NC}"
            echo "  quick fullstack <name>    Create fullstack web project (Next.js + Node.js API)"
            echo "  quick mobile <name>       Create mobile project (React Native + Node.js API)"
            echo "  quick ml <name>           Create ML platform (Python ML + Dashboard + API)"
            echo ""
            echo -e "${YELLOW}Session Management:${NC}"
            echo "  start                     Start development session (open terminals)"
            echo "  stop                      Stop all services"
            echo "  status                    Show project and service status"
            echo ""
            echo -e "${YELLOW}Service Management:${NC}"
            echo "  services start            Start database services"
            echo "  services stop             Stop database services" 
            echo "  services restart          Restart database services"
            echo ""
            echo -e "${YELLOW}Examples:${NC}"
            echo "  multi-dev quick fullstack ecommerce"
            echo "  multi-dev quick mobile chat-app"
            echo "  multi-dev quick ml recommendation-engine"
            echo ""
            echo -e "${BLUE}💡 After creating a project, cd into it and run 'multi-dev start'${NC}"
            ;;
    esac
}

# Run main function
main "$@"