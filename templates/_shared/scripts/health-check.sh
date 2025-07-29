#!/usr/bin/env bash

# Health check script for development environments
# Verifies that all required tools and services are available and working

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Icons
CHECK="✅"
CROSS="❌"
WARNING="⚠️"
INFO="ℹ️"

# Helper functions
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🩺 Development Environment Health Check${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo -e "\n${BLUE}$1${NC}"
    echo "────────────────────────────────────────────────────────────────────────────────"
}

check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    local required="${3:-true}"
    
    if command -v "$cmd" &> /dev/null; then
        local version
        case "$cmd" in
            node) version=$(node --version) ;;
            npm) version=$(npm --version) ;;
            python*) version=$(python --version 2>&1) ;;
            docker) version=$(docker --version) ;;
            git) version=$(git --version) ;;
            *) version="available" ;;
        esac
        echo -e "${CHECK} ${GREEN}$name${NC} ($version)"
        return 0
    else
        if [ "$required" = "true" ]; then
            echo -e "${CROSS} ${RED}$name${NC} (required but not found)"
            return 1
        else
            echo -e "${WARNING} ${YELLOW}$name${NC} (optional, not found)"
            return 0
        fi
    fi
}

check_service() {
    local service="$1"
    local port="$2"
    local name="${3:-$service}"
    
    if nc -z localhost "$port" 2>/dev/null; then
        echo -e "${CHECK} ${GREEN}$name${NC} (running on port $port)"
        return 0
    else
        echo -e "${INFO} ${YELLOW}$name${NC} (not running on port $port)"
        return 1
    fi
}

check_directory() {
    local dir="$1"
    local name="${2:-$dir}"
    local required="${3:-false}"
    
    if [ -d "$dir" ]; then
        echo -e "${CHECK} ${GREEN}$name${NC} ($dir)"
        return 0
    else
        if [ "$required" = "true" ]; then
            echo -e "${CROSS} ${RED}$name${NC} ($dir not found)"
            return 1
        else
            echo -e "${INFO} ${YELLOW}$name${NC} ($dir not found)"
            return 0
        fi
    fi
}

check_file() {
    local file="$1"
    local name="${2:-$file}"
    local required="${3:-false}"
    
    if [ -f "$file" ]; then
        echo -e "${CHECK} ${GREEN}$name${NC} ($file)"
        return 0
    else
        if [ "$required" = "true" ]; then
            echo -e "${CROSS} ${RED}$name${NC} ($file not found)"
            return 1
        else
            echo -e "${INFO} ${YELLOW}$name${NC} ($file not found)"
            return 0
        fi
    fi
}

# Main health check function
main() {
    print_header
    
    local exit_code=0
    
    # Check system requirements
    print_section "System Requirements"
    check_command "git" "Git" || exit_code=1
    check_command "curl" "cURL" || exit_code=1
    check_command "jq" "jq (JSON processor)" false
    check_command "which" "which" || exit_code=1
    
    # Check development tools based on environment
    if [ -n "$NODE_ENV" ] || [ -f "package.json" ]; then
        print_section "Node.js Environment"
        check_command "node" "Node.js" || exit_code=1
        check_command "npm" "npm" || exit_code=1
        check_command "yarn" "Yarn" false
        check_command "pnpm" "pnpm" false
    fi
    
    if [ -n "$PYTHON_ENV" ] || [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
        print_section "Python Environment"
        check_command "python" "Python" || exit_code=1
        check_command "pip" "pip" || exit_code=1
        check_command "python3" "Python 3" false
    fi
    
    if [ -f "Cargo.toml" ]; then
        print_section "Rust Environment"
        check_command "rustc" "Rust Compiler" || exit_code=1
        check_command "cargo" "Cargo" || exit_code=1
    fi
    
    if [ -f "go.mod" ]; then
        print_section "Go Environment"
        check_command "go" "Go" || exit_code=1
    fi
    
    # Check container tools
    if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ]; then
        print_section "Container Tools"
        check_command "docker" "Docker" || exit_code=1
        check_command "docker-compose" "Docker Compose" false
    fi
    
    # Check database services
    print_section "Database Services"
    check_service "postgres" "5432" "PostgreSQL"
    check_service "redis" "6379" "Redis"
    check_service "mongo" "27017" "MongoDB"
    
    # Check common development services
    print_section "Development Services"
    check_service "http" "3000" "Development Server"
    check_service "http" "8080" "Alt Development Server"
    check_service "http" "8888" "Jupyter Lab"
    
    # Check project structure
    print_section "Project Structure"
    check_directory "src" "Source Directory"
    check_directory "tests" "Tests Directory"
    check_directory "docs" "Documentation"
    check_file ".gitignore" "Git Ignore File"
    check_file "README.md" "README File"
    
    # Check environment variables
    print_section "Environment Variables"
    if [ -n "$NODE_ENV" ]; then
        echo -e "${CHECK} ${GREEN}NODE_ENV${NC} ($NODE_ENV)"
    fi
    if [ -n "$PYTHON_ENV" ]; then
        echo -e "${CHECK} ${GREEN}PYTHON_ENV${NC} ($PYTHON_ENV)"
    fi
    if [ -n "$DATABASE_URL" ]; then
        echo -e "${CHECK} ${GREEN}DATABASE_URL${NC} (configured)"
    fi
    
    # Summary
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${CHECK} ${GREEN}Health check completed successfully!${NC}"
        echo -e "${INFO} ${BLUE}All required tools and services are available.${NC}"
    else
        echo -e "${CROSS} ${RED}Health check failed!${NC}"
        echo -e "${WARNING} ${YELLOW}Some required tools or services are missing.${NC}"
        echo -e "${INFO} ${BLUE}Please install missing dependencies and try again.${NC}"
    fi
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    exit $exit_code
}

# Run health check
main "$@"