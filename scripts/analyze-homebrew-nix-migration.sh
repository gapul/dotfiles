#!/bin/bash

# Homebrew to Nix Migration Analysis Script
set -euo pipefail

# Current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Applications that are commonly available in nixpkgs
KNOWN_NIX_APPS=(
    # Development tools
    "docker"           # docker (container runtime)
    "firefox"          # firefox (browser) 
    "vlc"              # vlc (media player)
    "obs-studio"       # obs (screen recording)
    "gimp"             # gimp (image editor)
    "inkscape"         # inkscape (vector graphics)
    "krita"            # krita (digital painting)
    "thunderbird"      # thunderbird (email client)
    "blender"          # blender (3D modeling)
    "libreoffice"      # libreoffice (office suite)
    "qbittorrent"      # qbittorrent (torrent client)
    
    # Fonts (nerd-fonts collection)
    "nerd-fonts.hack"
    "nerd-fonts.fira-code"
    "nerd-fonts.jetbrains-mono"
    "nerd-fonts.source-code-pro"
    "nerd-fonts.ubuntu-mono"
)

# macOS-specific apps that likely won't work in nix
MACOS_SPECIFIC_APPS=(
    "raycast"
    "karabiner-elements"
    "wezterm"           # Terminal emulator (available in nix but cask version has macOS integrations)
    "claude"            # AI assistant (proprietary)
    "chatgpt"           # AI assistant (proprietary)
    "epic-games"        # Game launcher (proprietary)
    "steam"             # Game launcher (proprietary)
    "discord"           # Chat app (proprietary, has nix version but cask preferred)
    "slack"             # Chat app (proprietary, has nix version but cask preferred)
    "zoom"              # Video call app (proprietary)
    "spotify"           # Music streaming (proprietary)
)

# Function to check if app is available in nixpkgs
check_nix_availability() {
    local app="$1"
    local nix_name="$2"
    
    log_info "Checking availability of $app as $nix_name in nixpkgs..."
    
    # Use nix eval to check if package exists
    if nix eval "nixpkgs#$nix_name" --apply 'pkg: pkg.pname or pkg.name or "unknown"' 2>/dev/null | grep -q "unknown"; then
        echo "❌ $app ($nix_name) - Not available or problematic"
        return 1
    else
        echo "✅ $app ($nix_name) - Available in nixpkgs"
        return 0
    fi
}

# Main analysis function
analyze_migration_potential() {
    log_info "=== Homebrew to Nix Migration Analysis ==="
    
    local available_count=0
    local total_checked=0
    
    echo ""
    echo "🔍 Checking known applications available in nixpkgs:"
    echo ""
    
    for app in "${KNOWN_NIX_APPS[@]}"; do
        # Extract app name and nix package name
        if [[ "$app" == *"."* ]]; then
            # Handle nerd-fonts format
            app_name="${app#*.}"
            nix_name="$app"
        else
            app_name="$app"
            nix_name="$app"
        fi
        
        total_checked=$((total_checked + 1))
        if check_nix_availability "$app_name" "$nix_name"; then
            available_count=$((available_count + 1))
        fi
    done
    
    echo ""
    log_info "=== Migration Recommendations ==="
    echo ""
    
    echo "📦 HIGH PRIORITY - Can likely migrate to nix:"
    echo "  • docker -> pkgs.docker"
    echo "  • firefox -> pkgs.firefox" 
    echo "  • vlc -> pkgs.vlc"
    echo "  • obs-studio -> pkgs.obs-studio"
    echo "  • gimp -> pkgs.gimp"
    echo "  • inkscape -> pkgs.inkscape"
    echo "  • krita -> pkgs.krita"
    echo "  • thunderbird -> pkgs.thunderbird"
    echo "  • libreoffice -> pkgs.libreoffice"
    
    echo ""
    echo "⚠️  MEDIUM PRIORITY - Nix versions exist but cask may be preferred:"
    echo "  • visual-studio-code (nix: vscodium or vscode)"
    echo "  • discord (better macOS integration via cask)"
    echo "  • slack (better macOS integration via cask)"
    
    echo ""
    echo "❌ KEEP IN HOMEBREW - macOS-specific or proprietary:"
    echo "  • raycast (macOS-specific launcher)"
    echo "  • karabiner-elements (macOS keyboard customizer)"
    echo "  • claude, chatgpt (proprietary AI apps)"
    echo "  • epic-games, steam (game launchers with macOS optimizations)"
    
    echo ""
    log_success "Analysis complete: $available_count/$total_checked apps can migrate to nix"
    
    return 0
}

# Generate migration script
generate_migration_script() {
    local migration_file="$DOTFILES_DIR/scripts/phase4-nix-app-migration.sh"
    
    log_info "Generating Phase 4 migration script: $migration_file"
    
    cat > "$migration_file" << 'EOF'
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
EOF

    chmod +x "$migration_file"
    log_success "Generated migration script: $migration_file"
}

# System optimization recommendations
suggest_optimizations() {
    log_info "=== System Optimization Opportunities ==="
    echo ""
    
    echo "🚀 AUTOMATION IMPROVEMENTS:"
    echo ""
    echo "1. 📅 Scheduled Maintenance"
    echo "   • Add launchd plist for weekly nix garbage collection"
    echo "   • Automate dependency analysis reports"
    echo "   • Schedule CI health checks"
    echo ""
    
    echo "2. 🔄 Build Optimization"
    echo "   • Configure binary cache (cache.nixos.org + cachix)"
    echo "   • Enable nix-daemon auto-optimization"
    echo "   • Implement parallel builds (max-jobs = auto)"
    echo ""
    
    echo "3. 🛡️ Security Automation" 
    echo "   • Auto-update flake.lock weekly"
    echo "   • Automated security scanning integration"
    echo "   • CVE monitoring for nix packages"
    echo ""
    
    echo "4. 📊 Monitoring & Analytics"
    echo "   • System performance metrics collection"
    echo "   • Build time optimization tracking"
    echo "   • Package usage analytics"
    echo ""
    
    echo "5. 🤖 AI-Enhanced Features"
    echo "   • Claude Code integration for automatic issue resolution"
    echo "   • Intelligent package recommendation system" 
    echo "   • Automated configuration optimization suggestions"
}

# Main execution
main() {
    analyze_migration_potential
    echo ""
    generate_migration_script
    echo ""
    suggest_optimizations
    
    log_success "=== Analysis Complete ==="
    echo ""
    echo "Next steps:"
    echo "1. Review migration recommendations above"
    echo "2. Run ./scripts/phase4-nix-app-migration.sh migrate"
    echo "3. Implement suggested system optimizations"
}

# Execute main function
main "$@"