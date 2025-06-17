# Dotfiles Management Justfile
# This file defines common tasks and workflows for the dotfiles system
# Usage: just <task-name>

# Default recipe - show available commands
default:
    @just --list

# System rebuild and management
rebuild:
    @echo "🔄 Rebuilding nix-darwin system configuration..."
    nix run nix-darwin -- switch --flake .

home-rebuild:
    @echo "🏠 Rebuilding home-manager configuration..."
    home-manager switch --flake .

# Quick aliases for rebuild
nrs: rebuild
hms: home-rebuild

# Full system update
update:
    @echo "📦 Updating flake inputs..."
    nix flake update
    @echo "🔄 Rebuilding system with updated packages..."
    just rebuild

# Testing and validation
test:
    @echo "🧪 Running comprehensive system tests..."
    ./install.sh --help
    @echo "✅ Testing Nix configuration syntax..."
    nix flake check
    @echo "✅ Testing home.nix configuration..."
    home-manager build --flake .
    @echo "✅ All tests completed successfully"

lint:
    @echo "🔍 Running linting and syntax checks..."
    @echo "Checking shell scripts..."
    find . -name "*.sh" -type f -exec shellcheck {} \;
    @echo "Validating TOML files..."
    python3 .github/scripts/validate_toml.py
    @echo "Checking JSON files..."
    find configs -name "*.json" -type f -exec jq empty {} \;
    @echo "✅ All lint checks passed"

# Documentation generation
docs:
    @echo "📚 Generating documentation..."
    @echo "Creating dependency graph..."
    scripts/check-dependencies.sh --verbose
    @echo "Running system analysis..."
    scripts/system-analyzer.sh full-analysis
    @echo "✅ Documentation updated"

# Cleanup and maintenance
clean:
    @echo "🧹 Cleaning up system..."
    nix-collect-garbage -d
    @echo "Cleaning Homebrew cache..."
    brew cleanup
    @echo "✅ Cleanup completed"

gc: clean

# Development workflows
dev-shell:
    @echo "🚀 Entering development shell..."
    nix develop

dev-python:
    @echo "🐍 Entering Python development environment..."
    nix develop .#python

dev-node:
    @echo "📦 Entering Node.js development environment..."
    nix develop .#node

dev-rust:
    @echo "🦀 Entering Rust development environment..."
    nix develop .#rust

# Backup and restore operations
backup:
    @echo "💾 Creating configuration backup..."
    ./install.sh --list-backups
    @echo "Current backups:"
    ls -la backups/ 2>/dev/null || echo "No backups found"

list-backups: backup

# Secret management with sops-nix
secrets-init:
    @echo "🔐 Initializing SOPS secrets management..."
    @echo "1. Generating age key..."
    mkdir -p ~/.config/sops/age
    age-keygen -o ~/.config/sops/age/keys.txt
    @echo "2. Copy your public key and set SOPS_AGE_RECIPIENTS:"
    @echo "   export SOPS_AGE_RECIPIENTS=\"$(grep 'public key:' ~/.config/sops/age/keys.txt | cut -d: -f2 | tr -d ' ')\""
    @echo "3. Create secrets.yaml from template:"
    @echo "   cp secrets.yaml.example secrets.yaml"
    @echo "4. Edit and encrypt:"
    @echo "   sops secrets.yaml"

secrets-edit:
    @echo "✏️  Editing encrypted secrets..."
    sops secrets.yaml

# System analysis and optimization
analyze:
    @echo "📊 Running system analysis..."
    scripts/system-analyzer.sh full-analysis

analyze-packages:
    @echo "📦 Analyzing package optimization..."
    scripts/system-analyzer.sh package-optimize

analyze-apps:
    @echo "📱 Discovering unmanaged applications..."
    scripts/system-analyzer.sh discover-apps

analyze-usage:
    @echo "📈 Analyzing usage patterns..."
    scripts/system-analyzer.sh usage-patterns

# Health checks
health:
    @echo "🏥 Running system health checks..."
    @echo "Checking Nix installation..."
    nix --version
    @echo "Checking nix-darwin status..."
    darwin-rebuild --version
    @echo "Checking home-manager status..."
    home-manager --version
    @echo "Checking git status..."
    git status --porcelain
    @echo "✅ Health check completed"

status: health

# Git workflows
commit *MESSAGE:
    @echo "📝 Committing changes..."
    git add .
    git commit -m "{{MESSAGE}}

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

push:
    @echo "⬆️  Pushing changes to remote..."
    git push origin main

# CI/CD helpers
ci-test:
    @echo "🔧 Running CI tests locally..."
    act -j lint
    act -j test-install

# Quick setup for new machines
bootstrap:
    @echo "🚀 Bootstrapping new machine..."
    @echo "1. Installing Nix..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    @echo "2. Cloning dotfiles..."
    git clone https://github.com/your-username/dotfiles.git ~/dotfiles
    @echo "3. Running initial setup..."
    cd ~/dotfiles && ./setup.sh
    @echo "✅ Bootstrap completed"

# Install script wrappers
install:
    @echo "⚙️  Running standard installation..."
    ./install.sh

install-force:
    @echo "⚠️  Running forced installation..."
    ./install.sh --force

# Formatting
fmt:
    @echo "🎨 Formatting Nix files..."
    find . -name "*.nix" -type f -exec nixpkgs-fmt {} \;
    @echo "✅ Formatting completed"

format: fmt

# Show system information
info:
    @echo "ℹ️  System Information"
    @echo "===================="
    @echo "OS: $(uname -s) $(uname -r)"
    @echo "Architecture: $(uname -m)"
    @echo "Hostname: $(hostname)"
    @echo "User: $(whoami)"
    @echo "Home: $HOME"
    @echo "Dotfiles: $(pwd)"
    @echo ""
    @echo "🔧 Tool Versions"
    @echo "==============="
    @nix --version
    @darwin-rebuild --version 2>/dev/null || echo "nix-darwin: not installed"
    @home-manager --version 2>/dev/null || echo "home-manager: not installed"
    @echo "Git: $(git --version)"
    @echo "Shell: $SHELL"

# Troubleshooting helpers
doctor:
    @echo "👩‍⚕️ Running system diagnostics..."
    @echo "Checking Nix store..."
    nix store verify --all || echo "⚠️  Nix store issues detected"
    @echo "Checking flake syntax..."
    nix flake check || echo "⚠️  Flake syntax issues detected"
    @echo "Checking home-manager configuration..."
    home-manager build --flake . || echo "⚠️  Home-manager configuration issues detected"
    @echo "Checking dependencies..."
    scripts/check-dependencies.sh || echo "⚠️  Dependency issues detected"
    @echo "✅ Diagnostics completed"

# Emergency rollback
rollback:
    @echo "🔙 Rolling back to previous generation..."
    nix-env --rollback
    darwin-rebuild --rollback