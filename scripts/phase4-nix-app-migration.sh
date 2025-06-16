#!/bin/bash

# Phase 4: Migrate Homebrew GUI applications to nix-darwin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Applications to migrate from Homebrew casks to nix packages
MIGRATE_APPS=(
    "docker:docker"
    "vlc:vlc"
    "obs:obs-studio"
    "gimp:gimp"
    "inkscape:inkscape"
    "krita:krita"
    "thunderbird:thunderbird"
    "libreoffice:libreoffice"
)

migrate_apps() {
    log_info "=== Phase 4: GUI Application Migration ==="
    
    # Backup current darwin.nix
    cp "$DOTFILES_DIR/nix/darwin.nix" "$DOTFILES_DIR/nix/darwin.nix.phase4.backup"
    log_success "Backed up darwin.nix"
    
    # Add applications to nix environment.systemPackages
    local apps_to_add=""
    for app_pair in "${MIGRATE_APPS[@]}"; do
        local nix_name="${app_pair#*:}"
        apps_to_add="$apps_to_add    $nix_name\n"
    done
    
    log_info "Adding applications to nix darwin.nix:"
    echo -e "$apps_to_add"
    
    # Note: Manual editing required as app placement is context-dependent
    log_warning "Manual step required:"
    log_warning "Please add these packages to environment.systemPackages in nix/darwin.nix:"
    echo -e "$apps_to_add"
    
    return 0
}

# Main execution
case "${1:-}" in
    "migrate")
        migrate_apps
        ;;
    "verify")
        log_info "Verifying migrated applications..."
        for app_pair in "${MIGRATE_APPS[@]}"; do
            local cask_name="${app_pair%:*}"
            local nix_name="${app_pair#*:}"
            
            if command -v "$nix_name" >/dev/null 2>&1; then
                log_success "$nix_name available via nix"
            else
                log_warning "$nix_name not found in PATH"
            fi
        done
        ;;
    *)
        echo "Usage: $0 {migrate|verify}"
        echo ""
        echo "Commands:"
        echo "  migrate  - Start Phase 4 GUI application migration"
        echo "  verify   - Verify migrated applications are available"
        exit 1
        ;;
esac
