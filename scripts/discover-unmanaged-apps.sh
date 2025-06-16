#!/bin/bash

# Discover Unmanaged Applications Script
set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_highlight() { echo -e "${PURPLE}[DISCOVER]${NC} $1"; }

# Additional applications found that could be managed by nix
ADDITIONAL_NIX_CANDIDATES=(
    # Terminal applications
    "alacritty"       # Modern terminal emulator
    "kitty"           # GPU-based terminal
    "iterm2"          # Popular macOS terminal
    
    # Development tools  
    "android-studio"  # Android development
    "sublime-text"    # Text editor
    "atom"            # GitHub's editor (deprecated but might be installed)
    "brackets"        # Adobe's editor
    "postman"         # API testing
    "insomnia"        # API client
    "sourcetree"      # Git GUI
    "gitkriken"       # Git GUI
    
    # Browsers
    "brave-browser"   # Privacy browser
    "opera"           # Opera browser
    "microsoft-edge"  # Edge browser
    
    # Media tools
    "audacity"        # Audio editor
    "openshot"        # Video editor
    "kdenlive"        # Video editor
    "handbrake"       # Video transcoder
    "mpv"             # Media player
    "spotify"         # Music streaming
    
    # Design tools
    "figma"           # Design tool (but only desktop)
    "sketch"          # macOS design tool
    "affinity-designer" # Vector design
    "affinity-photo"  # Photo editing
    
    # Productivity
    "notion"          # Note-taking
    "evernote"        # Note-taking
    "typora"          # Markdown editor
    "mark-text"       # Markdown editor
    "logseq"          # Knowledge management
    
    # Communication
    "telegram"        # Messaging
    "whatsapp"        # Messaging
    "signal"          # Secure messaging
    "zoom"            # Video calls
    "teams"           # Microsoft Teams
    
    # Utilities
    "1password"       # Password manager
    "lastpass"        # Password manager
    "dashlane"        # Password manager
    "cleanmymac"      # System cleaner
    "alfred"          # Launcher
    "bartender"       # Menu bar organizer
    "magnet"          # Window manager
    "rectangle"       # Window manager
    "spectacle"       # Window manager
    "hammerspoon"     # Automation tool
)

check_nix_availability_fast() {
    local app="$1"
    
    # Quick check using nix eval (faster than full search)
    if nix eval "nixpkgs#$app" --apply 'pkg: pkg.name or "notfound"' 2>/dev/null | grep -q "notfound"; then
        return 1
    else
        return 0
    fi
}

# Discover installed but unmanaged applications
discover_unmanaged_apps() {
    log_info "=== Discovering Unmanaged Applications ==="
    echo ""
    
    # Get list of currently installed apps
    local installed_apps
    installed_apps=$(find /Applications -name "*.app" -maxdepth 1 -exec basename {} \; | sed 's/.app$//' | sort)
    
    log_highlight "Found $(echo "$installed_apps" | wc -l | tr -d ' ') total applications in /Applications"
    echo ""
    
    # Check which of our candidates are installed and available in nix
    local found_candidates=()
    
    echo "🔍 Checking for additional nix-manageable applications:"
    echo ""
    
    for app in "${ADDITIONAL_NIX_CANDIDATES[@]}"; do
        # Convert app name to likely app bundle name
        local app_variations=(
            "$app"
            "$(echo "$app" | sed 's/-/ /g' | sed 's/\b\w/\U&/g')"
            "${app//-/}"
            "${app//browser/Browser}"
        )
        
        local found_installed=false
        for variation in "${app_variations[@]}"; do
            if echo "$installed_apps" | grep -qi "$variation"; then
                found_installed=true
                break
            fi
        done
        
        if [[ "$found_installed" == "true" ]]; then
            if check_nix_availability_fast "$app" 2>/dev/null; then
                echo "  ✅ $app - Installed and available in nix"
                found_candidates+=("$app")
            else
                echo "  ⚠️  $app - Installed but not available in nix"
            fi
        fi
    done
    
    echo ""
    
    if [[ ${#found_candidates[@]} -gt 0 ]]; then
        log_success "Found ${#found_candidates[@]} additional applications that can be migrated to nix!"
        echo ""
        echo "📦 Additional nix migration candidates:"
        for candidate in "${found_candidates[@]}"; do
            echo "  • $candidate"
        done
        
        # Generate addition to darwin.nix
        echo ""
        log_highlight "Add these to nix/darwin.nix environment.systemPackages:"
        echo ""
        echo "    # Additional discovered applications"
        for candidate in "${found_candidates[@]}"; do
            echo "    $candidate"
        done
    else
        log_info "No additional nix-manageable applications found"
    fi
}

# Check specific high-value applications
check_high_value_apps() {
    log_info "=== Checking High-Value Applications ==="
    echo ""
    
    # High-value apps that are commonly installed
    local high_value_apps=(
        "telegram-desktop:Telegram"
        "signal-desktop:Signal"
        "notion-app-enhanced:Notion"
        "logseq:Logseq"
        "typora:Typora"
        "mpv:mpv"
        "audacity:Audacity"
        "handbrake:HandBrake"
        "rectangle:Rectangle"
        "hammerspoon:Hammerspoon"
        "alfred:Alfred"
        "1password:1Password"
    )
    
    local additional_found=()
    
    for app_pair in "${high_value_apps[@]}"; do
        local nix_name="${app_pair%:*}"
        local app_name="${app_pair#*:}"
        
        # Check if app is installed
        if find /Applications -name "${app_name}.app" -maxdepth 1 >/dev/null 2>&1; then
            if check_nix_availability_fast "$nix_name" 2>/dev/null; then
                echo "  ✅ $app_name → $nix_name (High value application)"
                additional_found+=("$nix_name")
            else
                echo "  ❌ $app_name - Installed but no nix package"
            fi
        fi
    done
    
    if [[ ${#additional_found[@]} -gt 0 ]]; then
        echo ""
        log_success "High-value applications found: ${#additional_found[@]}"
        echo ""
        echo "🎯 Add these high-value apps to nix:"
        echo ""
        echo "    # High-value applications discovered"
        for app in "${additional_found[@]}"; do
            echo "    $app"
        done
        
        # Update our Phase 5 script with additional apps
        echo ""
        log_highlight "Total additional apps for Phase 5+: $((28 + ${#additional_found[@]}))"
    fi
}

# Main execution
main() {
    discover_unmanaged_apps
    echo ""
    check_high_value_apps
    
    echo ""
    log_success "Discovery complete! Review findings above for additional nix migration opportunities."
}

main "$@"