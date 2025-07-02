# Multi-Platform Dotfiles Management Justfile
# Supports: macOS, Linux (NixOS + non-NixOS), WSL, Android
# Usage: just <task-name>

# Default recipe - show available commands
default:
    @just --list

# Platform detection
detect-platform:
    @echo "🔍 Detecting current platform..."
    @echo "System: $(uname -s)"
    @echo "Architecture: $(uname -m)"
    @if [ -f "/etc/nixos/configuration.nix" ]; then \
       echo "Platform: NixOS"; \
    elif [ -n "${WSL_DISTRO_NAME:-}" ]; then \
       echo "Platform: WSL"; \
    elif [ -d "/data/data/com.termux" ]; then \
       echo "Platform: Android/Termux"; \
    elif [ "$(uname -s)" = "Darwin" ]; then \
       echo "Platform: macOS"; \
    elif [ "$(uname -s)" = "Linux" ]; then \
       echo "Platform: Linux"; \
    else \
       echo "Platform: Unknown"; \
    fi

# Platform-specific rebuild commands
rebuild:
    @echo "🔄 Rebuilding configuration for current platform..."
    @if [ "$(uname -s)" = "Darwin" ]; then \
       just rebuild-darwin; \
    elif [ -f "/etc/nixos/configuration.nix" ]; then \
       just rebuild-nixos; \
    elif [ -n "${WSL_DISTRO_NAME:-}" ]; then \
       just rebuild-wsl; \
    elif [ -d "/data/data/com.termux" ]; then \
       just rebuild-android; \
    elif [ "$(uname -s)" = "Linux" ]; then \
       just rebuild-linux; \
    else \
       echo "❌ Unsupported platform"; \
       exit 1; \
    fi

# macOS rebuild (nix-darwin) 
rebuild-darwin:
    @echo "🍎 Rebuilding macOS configuration..."
    nix run nix-darwin -- switch --flake .

# macOS rebuild with sudo (warning-free)
rebuild-darwin-sudo:
    @echo "🍎 Rebuilding macOS configuration with sudo (warning-free)..."
    sudo -E nix run nix-darwin -- switch --flake . --impure

# Setup sudoers to eliminate warnings completely
setup-nix-darwin-sudo:
    @echo "🔧 Setting up sudoers for nix-darwin..."
    ./scripts/setup-nix-darwin-sudo.sh

# NixOS rebuild
rebuild-nixos:
    @echo "🐧 Rebuilding NixOS configuration..."
    sudo nixos-rebuild switch --flake .#linux-desktop

# Generic Linux rebuild (home-manager)
rebuild-linux:
    @echo "🐧 Rebuilding Linux home-manager configuration..."
    home-manager switch --flake .#yuki@linux

# WSL rebuild
rebuild-wsl:
    @echo "🪟 Rebuilding WSL configuration..."
    home-manager switch --flake .#yuki@wsl

# Android rebuild (nix-on-droid)
rebuild-android:
    @echo "🤖 Rebuilding Android configuration..."
    nix-on-droid switch --flake .#android

# Quick aliases for rebuild
nrs: rebuild
darwin: rebuild-darwin
linux: rebuild-linux
nixos: rebuild-nixos
wsl: rebuild-wsl
android: rebuild-android

# Platform-specific home-manager
home-rebuild:
    @if [ "$(uname -s)" = "Darwin" ]; then \
       echo "🏠 Rebuilding home-manager (macOS)..."; \
       home-manager switch --flake .#yuki@darwin; \
    elif [ -n "${WSL_DISTRO_NAME:-}" ]; then \
       echo "🏠 Rebuilding home-manager (WSL)..."; \
       home-manager switch --flake .#yuki@wsl; \
    elif [ "$(uname -s)" = "Linux" ]; then \
       echo "🏠 Rebuilding home-manager (Linux)..."; \
       home-manager switch --flake .#yuki@linux; \
    else \
       echo "❌ Home-manager not available on this platform"; \
    fi

hms: home-rebuild

# System updates
update:
    @echo "📦 Updating flake inputs..."
    nix flake update
    @echo "🔄 Rebuilding with updated packages..."
    just rebuild

# Testing and validation
test:
    @echo "🧪 Running platform-specific tests..."
    @if [ "$(uname -s)" = "Darwin" ]; then \
       just test-darwin; \
    elif [ -f "/etc/nixos/configuration.nix" ]; then \
       just test-nixos; \
    elif [ -n "${WSL_DISTRO_NAME:-}" ]; then \
       just test-wsl; \
    elif [ -d "/data/data/com.termux" ]; then \
       just test-android; \
    elif [ "$(uname -s)" = "Linux" ]; then \
       just test-linux; \
    else \
       echo "❌ No tests available for this platform"; \
    fi

test-darwin:
    @echo "🧪 Testing macOS configuration..."
    nix flake check
    @echo "✅ Testing home-manager build..."
    home-manager build --flake .#yuki@darwin

test-nixos:
    @echo "🧪 Testing NixOS configuration..."
    nix flake check
    @echo "✅ Testing NixOS build..."
    nixos-rebuild dry-run --flake .#linux-desktop

test-linux:
    @echo "🧪 Testing Linux configuration..."
    nix flake check
    @echo "✅ Testing home-manager build..."
    home-manager build --flake .#yuki@linux

test-wsl:
    @echo "🧪 Testing WSL configuration..."
    nix flake check
    @echo "✅ Testing home-manager build..."
    home-manager build --flake .#yuki@wsl

test-android:
    @echo "🧪 Testing Android configuration..."
    nix flake check
    @echo "✅ Testing nix-on-droid build..."
    nix-on-droid build --flake .#android

# Linting and validation
lint:
    @echo "🔍 Running multi-platform linting..."
    @echo "Checking shell scripts..."
    find . -name "*.sh" -type f -exec shellcheck {} \;
    @echo "Validating TOML files..."
    python3 .github/scripts/validate_toml.py
    @echo "Checking Nix syntax..."
    nix flake check --show-trace
    @echo "✅ All lint checks passed"

# Documentation and analysis
docs:
    @echo "📚 Generating multi-platform documentation..."
    @echo "Platform detection results:" > reports/platform-analysis.md
    @just detect-platform >> reports/platform-analysis.md
    @echo "" >> reports/platform-analysis.md
    @echo "Running system analysis..."
    scripts/system-analyzer.sh full-analysis
    @echo "✅ Documentation updated"

# Platform-specific package analysis
analyze:
    @echo "📊 Running platform-specific analysis..."
    @if [ "$(uname -s)" = "Darwin" ]; then \
       scripts/system-analyzer.sh discover-apps --verbose; \
    else \
       echo "Running generic package analysis..."; \
       scripts/system-analyzer.sh package-optimize; \
    fi

# Cleanup and maintenance
clean:
    @echo "🧹 Cleaning up platform-specific caches..."
    @if [ "$(uname -s)" = "Darwin" ]; then \
       echo "Cleaning nix-darwin..."; \
       nix-collect-garbage -d; \
       echo "Cleaning Homebrew..."; \
       brew cleanup 2>/dev/null || echo "Homebrew not available"; \
    elif [ -f "/etc/nixos/configuration.nix" ]; then \
       echo "Cleaning NixOS..."; \
       sudo nix-collect-garbage -d; \
    elif [ -d "/data/data/com.termux" ]; then \
       echo "Cleaning Android/Termux..."; \
       nix-collect-garbage -d; \
       pkg autoclean 2>/dev/null || echo "pkg not available"; \
    else \
       echo "Cleaning generic Nix..."; \
       nix-collect-garbage -d; \
    fi
    @echo "✅ Cleanup completed"

gc: clean

# Development workflows
dev-shell:
    @echo "🚀 Entering development shell..."
    nix develop

dev-test:
    @echo "🧪 Entering testing shell..."
    nix develop .#test

# Backup and migration
backup:
    @echo "💾 Creating platform-specific backup..."
    @timestamp=$(date +%Y%m%d_%H%M%S); \
    platform=$(uname -s | tr '[:upper:]' '[:lower:]'); \
    backup_dir="backups/platform-backup-$platform-$timestamp"; \
    mkdir -p "$backup_dir"; \
    echo "Backing up to: $backup_dir"; \
    if [ "$(uname -s)" = "Darwin" ]; then \
       cp -r nix/platforms "$backup_dir/"; \
       cp -r configs "$backup_dir/" 2>/dev/null || true; \
       system_profiler SPSoftwareDataType > "$backup_dir/system-info.txt"; \
    elif [ "$(uname -s)" = "Linux" ]; then \
       cp -r nix/platforms "$backup_dir/"; \
       cp -r configs "$backup_dir/" 2>/dev/null || true; \
       uname -a > "$backup_dir/system-info.txt"; \
       lsb_release -a >> "$backup_dir/system-info.txt" 2>/dev/null || true; \
    fi; \
    echo "✅ Backup created: $backup_dir"

# Migration between platforms
migrate-to-platforms:
    @echo "🔄 Migrating to new multi-platform structure..."
    @echo "Creating backup of current configuration..."
    just backup
    @echo "Testing new platform structure..."
    nix flake check
    @echo "✅ Migration test completed"
    @echo "To complete migration, run: just switch-to-platforms"

switch-to-platforms:
    @echo "⚠️  Switching to multi-platform configuration..."
    @echo "This will replace your current setup!"
    @read -p "Are you sure? (y/N) " -n 1 -r; \
    echo; \
    if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
       echo "🔄 Switching to platforms structure..."; \
       mv nix nix-legacy-$(date +%Y%m%d) || true; \
       mv nix/platforms nix; \
       echo "✅ Switched to multi-platform configuration"; \
       echo "Run 'just rebuild' to apply new configuration"; \
    else \
       echo "❌ Migration cancelled"; \
    fi

# Platform-specific setup
setup-darwin:
    @echo "🍎 Setting up macOS environment..."
    @if ! command -v brew >/dev/null 2>&1; then \
       echo "Installing Homebrew..."; \
       /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
    fi
    @echo "Installing Nix (Determinate Systems)..."
    @curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    @echo "✅ macOS setup completed"

setup-linux:
    @echo "🐧 Setting up Linux environment..."
    @echo "Installing Nix (Determinate Systems)..."
    @curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    @echo "Installing home-manager..."
    @nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
    @nix-channel --update
    @nix-shell '<home-manager>' -A install
    @echo "✅ Linux setup completed"

setup-wsl:
    @echo "🪟 Setting up WSL environment..."
    @echo "Installing Nix (Determinate Systems)..."
    @curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    @echo "Installing WSL utilities..."
    @if command -v apt >/dev/null 2>&1; then \
       sudo apt update && sudo apt install -y wslu; \
    elif command -v dnf >/dev/null 2>&1; then \
       sudo dnf install -y wslu; \
    fi
    @echo "✅ WSL setup completed"

setup-android:
    @echo "🤖 Setting up Android/Termux environment..."
    @echo "Installing nix-on-droid..."
    @if [ -d "/data/data/com.termux" ]; then \
       pkg update && pkg install -y curl; \
       curl -fsSL https://github.com/nix-community/nix-on-droid/releases/latest/download/bootstrap-aarch64.sh | bash; \
    else \
       echo "❌ Not running in Termux environment"; \
       exit 1; \
    fi
    @echo "✅ Android setup completed"

# Status and information
status:
    @echo "📊 Multi-platform dotfiles status"
    @echo "================================="
    @just detect-platform
    @echo ""
    @echo "🔧 Tool Versions"
    @echo "==============="
    @nix --version 2>/dev/null || echo "Nix: not installed"
    @if [ "$(uname -s)" = "Darwin" ]; then \
       darwin-rebuild --version 2>/dev/null || echo "nix-darwin: not installed"; \
       brew --version 2>/dev/null | head -1 || echo "Homebrew: not installed"; \
    fi
    @home-manager --version 2>/dev/null || echo "home-manager: not installed"
    @if [ -d "/data/data/com.termux" ]; then \
       nix-on-droid --version 2>/dev/null || echo "nix-on-droid: not installed"; \
    fi
    @echo "Git: $(git --version 2>/dev/null || echo 'not installed')"
    @echo "Shell: $SHELL"
    @echo ""
    @echo "📂 Configuration Status"
    @echo "======================"
    @if [ -d "nix/platforms" ]; then \
       echo "✅ Multi-platform structure detected"; \
    else \
       echo "⚠️  Legacy structure detected - consider migration"; \
    fi

# Health checks and diagnostics
doctor:
    @echo "👩‍⚕️ Running platform-specific diagnostics..."
    @echo "Checking Nix installation..."
    @nix --version || echo "❌ Nix not installed"
    @echo "Checking flake syntax..."
    @cd nix/platforms && nix flake check --show-trace || echo "⚠️  Flake issues detected"
    @if [ "$(uname -s)" = "Darwin" ]; then \
       echo "Checking nix-darwin..."; \
       darwin-rebuild --version || echo "❌ nix-darwin not available"; \
       echo "Checking Homebrew..."; \
       brew doctor || echo "⚠️  Homebrew issues detected"; \
    fi
    @echo "Checking home-manager..."
    @cd nix/platforms && home-manager build --flake .#yuki@$(uname -s | tr '[:upper:]' '[:lower:]') || echo "⚠️  Home-manager configuration issues"
    @echo "✅ Diagnostics completed"

# Information display
info:
    @echo "ℹ️  Multi-Platform Dotfiles Information"
    @echo "======================================"
    @just detect-platform
    @echo ""
    @echo "📁 Supported Platforms:"
    @echo "  🍎 macOS (nix-darwin + Homebrew)"
    @echo "  🐧 Linux (NixOS + home-manager)"
    @echo "  🐧 Linux (Generic + home-manager)"
    @echo "  🪟 Windows WSL (home-manager + Windows integration)"
    @echo "  🤖 Android (nix-on-droid + Termux)"
    @echo ""
    @echo "🚀 Quick Start:"
    @echo "  just setup-<platform>  - Initial platform setup"
    @echo "  just rebuild           - Rebuild current platform"
    @echo "  just test             - Test configuration"
    @echo "  just doctor           - Run diagnostics"
    @echo ""
    @echo "📖 For more commands: just --list"

# Emergency rollback
rollback:
    @echo "🔙 Rolling back to previous generation..."
    @if [ "$(uname -s)" = "Darwin" ]; then \
       nix-env --rollback && darwin-rebuild --rollback; \
    elif [ -f "/etc/nixos/configuration.nix" ]; then \
       sudo nixos-rebuild --rollback; \
    elif [ -d "/data/data/com.termux" ]; then \
       nix-on-droid --rollback; \
    else \
       nix-env --rollback; \
    fi
    @echo "✅ Rollback completed"