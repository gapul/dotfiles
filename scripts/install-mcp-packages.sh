#!/bin/bash
# Install MCP packages via npm (post-Nix setup)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if npm is available (should be from Nix)
check_npm() {
    if ! command -v npm &> /dev/null; then
        log_error "npm not found. Make sure Nix configuration is applied."
        exit 1
    fi
    
    log_info "Using npm: $(which npm)"
    log_info "npm version: $(npm --version)"
}

# Install MCP packages globally
install_mcp_packages() {
    local packages=(
        "@modelcontextprotocol/server-filesystem"
        "@modelcontextprotocol/server-postgres"
        "@modelcontextprotocol/server-github"
        "@modelcontextprotocol/server-brave-search"
        "@modelcontextprotocol/server-puppeteer"
        "@executeautomation/playwright-mcp-server"
    )
    
    log_info "Installing MCP packages globally..."
    
    for package in "${packages[@]}"; do
        log_info "Installing $package..."
        if npm install -g "$package"; then
            log_success "Installed $package"
        else
            log_warning "Failed to install $package (may not be available)"
        fi
    done
}

# Verify installation
verify_installation() {
    log_info "Verifying MCP package installation..."
    
    local packages=(
        "@modelcontextprotocol/server-filesystem"
        "@modelcontextprotocol/server-postgres"
        "@modelcontextprotocol/server-github"
        "@modelcontextprotocol/server-brave-search"
        "@modelcontextprotocol/server-puppeteer"
        "@executeautomation/playwright-mcp-server"
    )
    
    for package in "${packages[@]}"; do
        if npm list -g "$package" >/dev/null 2>&1; then
            log_success "$package is installed"
        else
            log_warning "$package is not installed"
        fi
    done
    
    # Check npx access
    log_info "Testing npx access..."
    if npx --version >/dev/null 2>&1; then
        log_success "npx is working: $(npx --version)"
    else
        log_error "npx is not working"
        exit 1
    fi
}

# Test MCP server access
test_mcp_servers() {
    log_info "Testing MCP server accessibility..."
    
    # Test filesystem server
    if npx @modelcontextprotocol/server-filesystem --help >/dev/null 2>&1; then
        log_success "filesystem server is accessible"
    else
        log_warning "filesystem server test failed"
    fi
    
    # Add more tests as needed
}

# Main execution
main() {
    log_info "🔧 Installing MCP packages for Claude Code..."
    
    check_npm
    install_mcp_packages
    verify_installation
    test_mcp_servers
    
    log_success "🎉 MCP package installation completed!"
    log_info "You can now use the MCP servers with Claude Code."
    log_info "Run 'claude mcp list' to verify Claude configuration."
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi