#!/bin/bash

# Phase 5: Maximum Nix Migration
# Migrate all possible applications from Homebrew to nix
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

# Applications for maximum migration (Phase 5)
PHASE5_MIGRATIONS=(
    # Development tools
    "visual-studio-code:vscode"
    "zed:zed-editor"
    "virtualbox:virtualbox"
    "podman-desktop:podman-desktop"
    "godot:godot_4"
    "freecad:freecad"
    "kicad:kicad"
    "goxel:goxel"
    
    # Creative applications
    "scribus:scribus"
    "fontforge:fontforge"
    "natron:natron"
    "opentoonz:opentoonz"
    
    # Browsers
    "vivaldi:vivaldi"
    "tor-browser:tor-browser"
    
    # Media applications
    "musescore:musescore"
    "mixxx:mixxx"
    "surge-xt:surge-XT"
    
    # Gaming
    "prismlauncher:prismlauncher"
    
    # Productivity
    "obsidian:obsidian"
    "zotero:zotero"
    "bitwarden:bitwarden-desktop"
    "espanso:espanso"
    "syncthing:syncthing"
    "spacedrive:spacedrive"
    "rustdesk:rustdesk"
    "wireshark:wireshark"
    "onlyoffice:onlyoffice-bin"
    "ollama:ollama"
)

# Execute Phase 5 migration
execute_phase5_migration() {
    log_info "=== Phase 5: Maximum Nix Migration ==="
    
    # Backup current configuration
    cp "$DOTFILES_DIR/nix/darwin.nix" "$DOTFILES_DIR/nix/darwin.nix.phase5.backup"
    log_success "Configuration backed up"
    
    # Generate nix packages list
    log_info "Applications to migrate in Phase 5:"
    echo ""
    echo "    # Phase 5: Maximum Homebrew to Nix Migration"
    for app_pair in "${PHASE5_MIGRATIONS[@]}"; do
        local nix_name="${app_pair#*:}"
        local cask_name="${app_pair%:*}"
        echo "    $nix_name        # $cask_name"
    done
    
    echo ""
    log_warning "Manual step required:"
    log_warning "1. Add the above packages to environment.systemPackages in nix/darwin.nix"
    log_warning "2. Comment out corresponding casks in homebrew.casks"
    log_warning "3. Run: USER=yuki sudo darwin-rebuild switch --flake ~/.config/nix-darwin"
    
    return 0
}

# Verify migration
verify_phase5_migration() {
    log_info "=== Verifying Phase 5 Migration ==="
    
    local success_count=0
    local total_count=0
    
    for app_pair in "${PHASE5_MIGRATIONS[@]}"; do
        local nix_name="${app_pair#*:}"
        local cask_name="${app_pair%:*}"
        
        total_count=$((total_count + 1))
        
        # Check if nix version is available
        if nix eval "nixpkgs#$nix_name" --apply 'pkg: pkg.pname or "unknown"' >/dev/null 2>&1; then
            log_success "✅ $nix_name ($cask_name) - Available in nix"
            success_count=$((success_count + 1))
        else
            log_warning "❌ $nix_name ($cask_name) - Not available"
        fi
    done
    
    echo ""
    log_info "Migration verification: $success_count/$total_count apps available in nix"
    
    if [[ $success_count -eq $total_count ]]; then
        log_success "🎉 All Phase 5 applications verified and ready for migration!"
    else
        log_warning "Some applications may need alternative approaches"
    fi
}

# Generate strategic migration plan
generate_migration_plan() {
    log_info "=== Strategic Migration Plan ==="
    
    cat << 'PLAN'

📋 COMPLETE HOMEBREW TO NIX MIGRATION STRATEGY

🎯 PHASE 5 OBJECTIVES:
- Migrate 30+ additional applications to nix
- Achieve 85%+ nix management ratio
- Maintain macOS-specific tools via strategic Homebrew use
- Implement hybrid management optimization

🚀 IMPLEMENTATION STEPS:

1. PRE-MIGRATION PREPARATION:
   □ Backup current system state
   □ Verify all target packages in nixpkgs
   □ Test critical applications function

2. NIX CONFIGURATION UPDATE:
   □ Add Phase 5 packages to environment.systemPackages
   □ Organize packages by category (dev, creative, etc.)
   □ Comment out migrated Homebrew casks

3. SYSTEM REBUILD:
   □ Execute darwin-rebuild with new configuration
   □ Verify all applications launch correctly
   □ Test application functionality

4. OPTIMIZATION:
   □ Remove unused Homebrew dependencies
   □ Optimize nix build settings
   □ Configure application preferences

5. STRATEGIC HOMEBREW RETENTION:
   □ Keep macOS-specific tools (raycast, karabiner)
   □ Retain proprietary applications (claude, figma)
   □ Maintain Apple ecosystem integration

📊 EXPECTED RESULTS:
- Nix-managed packages: 130+ applications
- Homebrew-managed: 20+ strategic applications
- Management ratio: ~85% nix, 15% Homebrew
- System benefits: Better reproducibility, atomic updates

⚠️  RISKS & MITIGATION:
- Application compatibility → Thorough testing
- macOS integration loss → Keep essential tools in Homebrew
- Configuration complexity → Maintain documentation

🎉 SUCCESS CRITERIA:
- All migrated applications functional
- System performance maintained/improved
- Maintenance overhead reduced
- Full reproducibility achieved

PLAN

    log_success "Strategic migration plan generated"
}

# Main execution
main() {
    case "${1:-plan}" in
        "migrate")
            execute_phase5_migration
            ;;
        "verify")
            verify_phase5_migration
            ;;
        "plan")
            generate_migration_plan
            ;;
        *)
            echo "Usage: $0 {migrate|verify|plan}"
            echo ""
            echo "Commands:"
            echo "  migrate  - Execute Phase 5 maximum migration"
            echo "  verify   - Verify package availability in nixpkgs"
            echo "  plan     - Display strategic migration plan"
            exit 1
            ;;
    esac
}

main "$@"
