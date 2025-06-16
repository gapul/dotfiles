#!/bin/bash

# Complete Homebrew to Nix Migration Analysis
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_highlight() { echo -e "${PURPLE}[HIGHLIGHT]${NC} $1"; }

# Analyze complete migration feasibility
analyze_complete_migration() {
    log_info "=== Complete Homebrew to Nix Migration Analysis ==="
    echo ""
    
    # Current Homebrew casks from darwin.nix
    local remaining_casks=(
        # Core productivity (some can migrate)
        "raycast"              # ❌ macOS-specific launcher
        "karabiner-elements"   # ❌ macOS kernel extension
        "wezterm"              # ⚠️ Available in nix but cask has better macOS integration
        "visual-studio-code"   # ✅ Can migrate to nixpkgs.vscode
        
        # Development & Programming
        "cursor"               # ❌ Proprietary AI editor (not in nixpkgs)
        "zed"                  # ✅ Available in nixpkgs.zed-editor
        "figma"                # ❌ Proprietary design tool
        "virtualbox"           # ✅ Available in nixpkgs.virtualbox
        "podman-desktop"       # ✅ Available in nixpkgs.podman-desktop
        "unity-hub"            # ❌ Proprietary game engine
        "godot"                # ✅ Available in nixpkgs.godot_4
        "freecad"              # ✅ Available in nixpkgs.freecad
        "kicad"                # ✅ Available in nixpkgs.kicad
        "goxel"                # ✅ Available in nixpkgs.goxel
        
        # Creative & Design (some migrated in Phase 4)
        "scribus"              # ✅ Available in nixpkgs.scribus
        "fontforge"            # ✅ Available in nixpkgs.fontforge
        "material-maker"       # ❌ Godot-based tool (complex dependencies)
        "natron"               # ✅ Available in nixpkgs.natron
        "opentoonz"            # ✅ Available in nixpkgs.opentoonz
        
        # Browsers
        "zen"                  # ❌ Firefox fork (not in nixpkgs)
        "firefox@developer-edition"  # ⚠️ Special edition (nixpkgs has firefox-devedition-bin)
        "floorp"               # ❌ Firefox fork (not in nixpkgs)
        "vivaldi"              # ✅ Available in nixpkgs.vivaldi
        "google-chrome@dev"    # ⚠️ Dev channel (nixpkgs has google-chrome)
        "tor-browser"          # ✅ Available in nixpkgs.tor-browser
        
        # Media & Entertainment (some migrated)
        "musescore"            # ✅ Available in nixpkgs.musescore
        "mixxx"                # ✅ Available in nixpkgs.mixxx
        "surge-xt"             # ✅ Available in nixpkgs.surge-XT
        
        # Gaming & Emulation
        "steam"                # ⚠️ Available but macOS version has better integration
        "epic-games"           # ❌ Proprietary launcher
        "minecraft"            # ⚠️ Available as nixpkgs.minecraft-launcher
        "retroarch-metal"      # ⚠️ Metal optimized (nixpkgs has retroarch)
        "prismlauncher"        # ✅ Available in nixpkgs.prismlauncher
        "whisky"               # ❌ Wine wrapper for macOS (not in nixpkgs)
        
        # Communication & Productivity
        "discord"              # ✅ Available but cask has better macOS integration
        "slack"                # ✅ Available but cask has better macOS integration
        "obsidian"             # ✅ Available in nixpkgs.obsidian
        "zotero"               # ✅ Available in nixpkgs.zotero
        
        # Utilities & System
        "bitwarden"            # ✅ Available in nixpkgs.bitwarden-desktop
        "espanso"              # ✅ Available in nixpkgs.espanso
        "shortcat"             # ❌ macOS-specific accessibility tool
        "middleclick"          # ❌ macOS-specific utility
        "jordanbaird-ice"      # ❌ macOS menu bar tool
        "syncthing"            # ✅ Available in nixpkgs.syncthing
        "spacedrive"           # ✅ Available in nixpkgs.spacedrive
        "rustdesk"             # ✅ Available in nixpkgs.rustdesk
        "wireshark"            # ✅ Available in nixpkgs.wireshark
        "cloudflare-warp"      # ❌ Proprietary VPN client
        "vmware-fusion"        # ❌ Proprietary virtualization
        
        # Office & Documents (some migrated)
        "onlyoffice"           # ✅ Available in nixpkgs.onlyoffice-bin
        "microsoft-excel"      # ❌ Proprietary Microsoft Office
        "microsoft-word"       # ❌ Proprietary Microsoft Office
        "microsoft-powerpoint" # ❌ Proprietary Microsoft Office
        
        # AI & Assistant tools
        "claude"               # ❌ Proprietary AI assistant
        "chatgpt"              # ❌ Proprietary AI assistant
        "ollama"               # ✅ Available in nixpkgs.ollama
        
        # Fonts (many can migrate to nerd-fonts)
        "font-hackgen-nerd"    # ✅ Use nerd-fonts.hackgen
        "font-udev-gothic-nf"  # ⚠️ Might be available as custom font
        "font-plemol-jp-nf"    # ⚠️ Might be available as custom font
        "font-cica"            # ⚠️ Japanese programming font
        "font-hack-nerd-font"  # ✅ Available in nerd-fonts.hack
        "font-sf-mono"         # ❌ Apple system font
        "font-sf-pro"          # ❌ Apple system font
        "sf-symbols"           # ❌ Apple system symbols
    )
    
    # Classification
    local can_migrate=0
    local mac_specific=0
    local proprietary=0
    local total=0
    
    log_highlight "=== Migration Analysis Results ==="
    echo ""
    
    echo "✅ CAN MIGRATE TO NIX (High confidence):"
    local migrable_apps=(
        "visual-studio-code → vscode"
        "zed → zed-editor"
        "virtualbox → virtualbox"
        "podman-desktop → podman-desktop"
        "godot → godot_4"
        "freecad → freecad"
        "kicad → kicad"
        "goxel → goxel"
        "scribus → scribus"
        "fontforge → fontforge"
        "natron → natron"
        "opentoonz → opentoonz"
        "vivaldi → vivaldi"
        "tor-browser → tor-browser"
        "musescore → musescore"
        "mixxx → mixxx"
        "surge-xt → surge-XT"
        "prismlauncher → prismlauncher"
        "obsidian → obsidian"
        "zotero → zotero"
        "bitwarden → bitwarden-desktop"
        "espanso → espanso"
        "syncthing → syncthing"
        "spacedrive → spacedrive"
        "rustdesk → rustdesk"
        "wireshark → wireshark"
        "onlyoffice → onlyoffice-bin"
        "ollama → ollama"
    )
    
    for app in "${migrable_apps[@]}"; do
        echo "  • $app"
        ((can_migrate++))
    done
    
    echo ""
    echo "⚠️  PARTIAL MIGRATION (nix available but cask might be better):"
    local partial_apps=(
        "wezterm → wezterm (but cask has better macOS integration)"
        "firefox@developer-edition → firefox-devedition-bin"
        "google-chrome@dev → google-chrome"
        "steam → steam (but macOS version optimized)"
        "minecraft → minecraft-launcher"
        "retroarch-metal → retroarch (loses Metal optimization)"
        "discord → discord (but cask has native features)"
        "slack → slack (but cask has native features)"
    )
    
    for app in "${partial_apps[@]}"; do
        echo "  • $app"
        ((can_migrate++))
    done
    
    echo ""
    echo "❌ MUST STAY IN HOMEBREW (macOS-specific or proprietary):"
    local stay_homebrew=(
        "raycast (macOS-specific launcher)"
        "karabiner-elements (kernel extension)"
        "cursor (proprietary AI editor)"
        "figma (proprietary design tool)"
        "unity-hub (proprietary game engine)"
        "material-maker (complex dependencies)"
        "zen (Firefox fork, not in nixpkgs)"
        "floorp (Firefox fork, not in nixpkgs)"
        "epic-games (proprietary launcher)"
        "whisky (macOS Wine wrapper)"
        "shortcat (macOS accessibility)"
        "middleclick (macOS utility)"
        "jordanbaird-ice (macOS menu bar)"
        "cloudflare-warp (proprietary VPN)"
        "vmware-fusion (proprietary VM)"
        "microsoft-office suite (proprietary)"
        "claude (proprietary AI)"
        "chatgpt (proprietary AI)"
        "Apple fonts (sf-mono, sf-pro, sf-symbols)"
    )
    
    for app in "${stay_homebrew[@]}"; do
        echo "  • $app"
        ((mac_specific++))
    done
    
    total=$((can_migrate + mac_specific))
    
    echo ""
    log_highlight "=== MIGRATION SUMMARY ==="
    echo ""
    printf "📊 Migration Analysis:\n"
    printf "  ✅ Can migrate to nix: %d apps (%d%%)\n" "$can_migrate" $((can_migrate * 100 / total))
    printf "  ❌ Must stay Homebrew: %d apps (%d%%)\n" "$mac_specific" $((mac_specific * 100 / total))
    printf "  📦 Total analyzed: %d apps\n" "$total"
    
    echo ""
    log_success "CONCLUSION: About 65% of Homebrew apps can migrate to nix!"
    log_warning "Complete migration impossible due to macOS-specific tools"
    log_info "Recommended: Hybrid approach (nix + strategic Homebrew)"
}

# Generate Phase 5 migration script
generate_phase5_script() {
    log_info "=== Generating Phase 5 Migration Script ==="
    
    local phase5_script="$DOTFILES_DIR/scripts/phase5-maximum-nix-migration.sh"
    
    cat > "$phase5_script" << 'EOF'
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
EOF

    chmod +x "$phase5_script"
    log_success "Phase 5 migration script generated: $phase5_script"
}

# Main execution
main() {
    analyze_complete_migration
    echo ""
    generate_phase5_script
    
    echo ""
    log_highlight "=== NEXT ACTIONS ==="
    echo ""
    echo "1. Review migration analysis results above"
    echo "2. Run: scripts/phase5-maximum-nix-migration.sh verify"
    echo "3. Run: scripts/phase5-maximum-nix-migration.sh plan"
    echo "4. Execute: scripts/phase5-maximum-nix-migration.sh migrate"
    echo ""
    log_success "Complete Homebrew migration analysis finished!"
}

main "$@"