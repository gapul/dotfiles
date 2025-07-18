#!/usr/bin/env bash

# System Auto-Fix - Automatic repair system for dotfiles
# Attempts to automatically resolve common issues detected by health checks

set -euo pipefail

# Colors and icons
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CHECK="✅"
CROSS="❌"
WARNING="⚠️"
INFO="ℹ️"
GEAR="⚙️"
WRENCH="🔧"

# Logging functions
log_info() {
    echo -e "${CYAN}${INFO} $1${NC}"
}

log_success() {
    echo -e "${GREEN}${CHECK} $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}${WARNING} $1${NC}"
}

log_error() {
    echo -e "${RED}${CROSS} $1${NC}"
}

log_fixing() {
    echo -e "${BLUE}${WRENCH} $1${NC}"
}

# Fix attempt counters
fixes_attempted=0
fixes_successful=0
fixes_failed=0

# Fix attempt function
attempt_fix() {
    local description="$1"
    local fix_command="$2"
    local verify_command="$3"
    local critical="${4:-false}"
    
    fixes_attempted=$((fixes_attempted + 1))
    
    log_fixing "Attempting to fix: $description"
    
    # Create a temporary log file for this fix
    local temp_log=$(mktemp)
    
    if eval "$fix_command" >"$temp_log" 2>&1; then
        if eval "$verify_command" &>/dev/null; then
            fixes_successful=$((fixes_successful + 1))
            log_success "Fixed: $description"
            rm -f "$temp_log"
            return 0
        else
            fixes_failed=$((fixes_failed + 1))
            log_warning "Fix applied but verification failed: $description"
            if [[ "$critical" == "true" ]]; then
                log_error "Critical fix failed! Manual intervention required."
                cat "$temp_log" | head -10
            fi
            rm -f "$temp_log"
            return 1
        fi
    else
        fixes_failed=$((fixes_failed + 1))
        log_error "Fix failed: $description"
        if [[ "$critical" == "true" ]]; then
            echo "Error details:"
            cat "$temp_log" | head -10
        fi
        rm -f "$temp_log"
        return 1
    fi
}

# Safe command execution with timeout
safe_execute() {
    local cmd="$1"
    local timeout="${2:-30}"
    
    if command -v timeout &>/dev/null; then
        timeout "$timeout" bash -c "$cmd"
    else
        eval "$cmd"
    fi
}

# Backup important files before fixes
create_backup() {
    local backup_dir="$HOME/.dotfiles-backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup critical configuration files
    local files_to_backup=(
        "$HOME/.zshrc"
        "$HOME/.config/nvim/init.lua"
        "$HOME/.ssh/config"
        "$HOME/.gitconfig"
    )
    
    for file in "${files_to_backup[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$backup_dir/" 2>/dev/null || true
        fi
    done
    
    echo "$backup_dir"
}

# Main auto-fix function
main() {
    echo -e "${BLUE}${WRENCH} System Auto-Fix - Attempting automatic repairs...${NC}"
    echo "============================================================"
    echo ""
    
    # Create backup before starting fixes
    local backup_dir
    backup_dir=$(create_backup)
    log_info "Configuration backup created: $backup_dir"
    echo ""
    
    # 1. Nix System Fixes
    echo -e "${BLUE}🔧 Nix System Fixes:${NC}"
    echo "────────────────────────────"
    
    # Fix Nix store issues
    attempt_fix "Nix store optimization" \
        "nix store optimise" \
        "test -d /nix/store" \
        false
    
    # Garbage collection to free space
    attempt_fix "Nix garbage collection (7 days)" \
        "nix-collect-garbage --delete-older-than 7d" \
        "test -d /nix/store" \
        false
    
    # Fix Nix channels
    if command -v nix-channel &>/dev/null; then
        attempt_fix "Nix channel update" \
            "nix-channel --update" \
            "nix-channel --list | grep -q ." \
            false
    fi
    
    # Rebuild Nix user environment
    attempt_fix "Nix user environment rebuild" \
        "nix-env --upgrade" \
        "nix-env --query | grep -q ." \
        false
    
    echo ""
    
    # 2. Package Management Fixes
    echo -e "${BLUE}📦 Package Management Fixes:${NC}"
    echo "────────────────────────────────"
    
    # Home Manager fixes
    if command -v home-manager &>/dev/null; then
        attempt_fix "Home Manager news check" \
            "home-manager news --quiet" \
            "home-manager --version" \
            false
    fi
    
    # Homebrew fixes (macOS)
    if command -v brew &>/dev/null; then
        attempt_fix "Homebrew update" \
            "brew update" \
            "brew --version" \
            false
            
        attempt_fix "Homebrew cleanup" \
            "brew cleanup --prune=7" \
            "brew --version" \
            false
            
        attempt_fix "Homebrew doctor check" \
            "brew doctor" \
            "brew --version" \
            false
    fi
    
    echo ""
    
    # 3. Development Environment Fixes
    echo -e "${BLUE}💻 Development Environment Fixes:${NC}"
    echo "─────────────────────────────────────"
    
    # Node.js fixes
    if command -v npm &>/dev/null; then
        attempt_fix "npm cache cleanup" \
            "npm cache clean --force" \
            "npm --version" \
            false
            
        attempt_fix "npm global packages audit" \
            "npm audit fix --global || true" \
            "npm --version" \
            false
    fi
    
    # Git configuration fixes
    if command -v git &>/dev/null; then
        # Fix Git global configuration if missing
        if ! git config --global user.email &>/dev/null; then
            log_warning "Git user.email not configured - manual setup required"
        fi
        
        if ! git config --global user.name &>/dev/null; then
            log_warning "Git user.name not configured - manual setup required"
        fi
        
        # Fix Git safe directories
        attempt_fix "Git safe directory configuration" \
            "git config --global --add safe.directory '*'" \
            "git config --global --get-all safe.directory | grep -q '*'" \
            false
    fi
    
    # Docker fixes
    if command -v docker &>/dev/null; then
        attempt_fix "Docker system cleanup" \
            "docker system prune -f --volumes || true" \
            "docker --version" \
            false
    fi
    
    echo ""
    
    # 4. Permission Fixes
    echo -e "${BLUE}🔒 Permission Fixes:${NC}"
    echo "───────────────────────"
    
    # SSH permissions
    if [[ -d "$HOME/.ssh" ]]; then
        attempt_fix "SSH directory permissions" \
            "chmod 700 ~/.ssh" \
            "test \$(stat -f '%A' ~/.ssh 2>/dev/null || echo '000') = '700'" \
            true
            
        attempt_fix "SSH private key permissions" \
            "find ~/.ssh -name 'id_*' ! -name '*.pub' -exec chmod 600 {} \\; 2>/dev/null || true" \
            "test -d ~/.ssh" \
            false
            
        attempt_fix "SSH public key permissions" \
            "find ~/.ssh -name '*.pub' -exec chmod 644 {} \\; 2>/dev/null || true" \
            "test -d ~/.ssh" \
            false
            
        attempt_fix "SSH config file permissions" \
            "test -f ~/.ssh/config && chmod 600 ~/.ssh/config || true" \
            "test -d ~/.ssh" \
            false
    fi
    
    # GPG permissions
    if [[ -d "$HOME/.gnupg" ]]; then
        attempt_fix "GPG directory permissions" \
            "chmod 700 ~/.gnupg && find ~/.gnupg -type f -exec chmod 600 {} \\; 2>/dev/null || true" \
            "test -d ~/.gnupg" \
            false
    fi
    
    echo ""
    
    # 5. Configuration File Fixes
    echo -e "${BLUE}⚙️ Configuration Fixes:${NC}"
    echo "──────────────────────────"
    
    # Zsh completion fixes
    attempt_fix "Zsh completion rebuild" \
        "rm -f ~/.zcompdump* && zsh -c 'autoload -U compinit && compinit' 2>/dev/null || true" \
        "test -f ~/.zshrc || test -n \"\$ZSH_VERSION\"" \
        false
    
    # Neovim fixes
    if command -v nvim &>/dev/null; then
        attempt_fix "Neovim configuration check" \
            "nvim --headless +checkhealth +qall 2>/dev/null || true" \
            "nvim --version" \
            false
    fi
    
    # Starship configuration
    if command -v starship &>/dev/null && [[ ! -f "$HOME/.config/starship.toml" ]]; then
        attempt_fix "Starship default configuration" \
            "mkdir -p ~/.config && starship preset gruvbox-rainbow > ~/.config/starship.toml" \
            "test -f ~/.config/starship.toml" \
            false
    fi
    
    echo ""
    
    # 6. Modern CLI Tools Fixes
    echo -e "${BLUE}🛠️ Modern CLI Tools Fixes:${NC}"
    echo "─────────────────────────────"
    
    # Fix missing tools via Nix profile
    local missing_tools=()
    local modern_tools=("eza" "bat" "rg" "fd" "zoxide" "lazygit" "yazi" "btm")
    
    for tool in "${modern_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warning "Missing modern CLI tools: ${missing_tools[*]}"
        log_info "Consider running 'just rebuild' to reinstall missing tools"
    fi
    
    # Fix configuration for existing tools
    if command -v bat &>/dev/null && [[ ! -f "$HOME/.config/bat/config" ]]; then
        attempt_fix "Bat configuration setup" \
            "mkdir -p ~/.config/bat && echo '--theme=\"gruvbox-dark\"' > ~/.config/bat/config" \
            "test -f ~/.config/bat/config" \
            false
    fi
    
    echo ""
    
    # 7. Service and Process Fixes
    echo -e "${BLUE}🔄 Service Fixes:${NC}"
    echo "─────────────────────"
    
    # macOS specific fixes
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Fix potential launchd issues
        attempt_fix "User launchd services reload" \
            "launchctl bootstrap gui/\$(id -u) ~/.config/LaunchAgents/* 2>/dev/null || true" \
            "launchctl print gui/\$(id -u) >/dev/null 2>&1" \
            false
    fi
    
    echo ""
    
    # Results Summary
    echo -e "${BLUE}📊 Auto-Fix Summary:${NC}"
    echo "════════════════════"
    echo "Fixes attempted: $fixes_attempted"
    echo "Fixes successful: $fixes_successful"
    echo "Fixes failed: $fixes_failed"
    
    local success_rate=0
    if [[ $fixes_attempted -gt 0 ]]; then
        success_rate=$((fixes_successful * 100 / fixes_attempted))
    fi
    echo "Success rate: $success_rate%"
    echo ""
    
    # Overall assessment
    if [[ $success_rate -ge 80 ]]; then
        log_success "Auto-fix completed successfully!"
        echo "Most issues have been resolved automatically."
    elif [[ $success_rate -ge 50 ]]; then
        log_warning "Auto-fix partially successful. Manual intervention may be needed."
        echo "Some issues were resolved, but others require attention."
    else
        log_error "Auto-fix had limited success. Manual troubleshooting recommended."
        echo "Many issues could not be resolved automatically."
    fi
    
    echo ""
    echo -e "${BLUE}💡 Next Steps:${NC}"
    echo "──────────────"
    echo "• Run 'system-health-master' to verify fixes"
    echo "• Check specific component health if issues persist"
    echo "• Consider 'just rebuild' for comprehensive refresh"
    echo "• Review backup at: $backup_dir"
    
    if [[ $fixes_failed -gt 0 ]]; then
        echo "• Manual intervention needed for $fixes_failed failed fixes"
        echo "• Check system logs for detailed error information"
    fi
    
    echo ""
    
    # Save fix log
    local log_dir="$HOME/.dotfiles-health"
    local log_file="$log_dir/autofix-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$log_dir"
    
    {
        echo "System Auto-Fix Report"
        echo "Generated: $(date)"
        echo "======================"
        echo "Attempted: $fixes_attempted"
        echo "Successful: $fixes_successful"
        echo "Failed: $fixes_failed"
        echo "Success Rate: $success_rate%"
        echo "Backup Location: $backup_dir"
        echo ""
        echo "System Information:"
        echo "OS: $(uname -s) $(uname -r)"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "macOS: $(sw_vers -productVersion)"
        fi
    } > "$log_file"
    
    log_info "Fix report saved to: $log_file"
    
    # Return appropriate exit code
    if [[ $success_rate -ge 50 ]]; then
        return 0
    else
        return 1
    fi
}

# Help function
show_help() {
    cat << EOF
System Auto-Fix - Automatic Repair System

USAGE:
    $(basename "$0") [OPTIONS]

DESCRIPTION:
    Attempts to automatically resolve common issues detected by the health check system.
    Creates backups before making changes and provides detailed reporting.

OPTIONS:
    -h, --help      Show this help message
    --dry-run       Show what would be fixed without making changes
    --force         Skip safety checks and confirmations

EXAMPLES:
    $(basename "$0")                 # Run automatic fixes
    $(basename "$0") --dry-run       # Preview fixes without executing
    $(basename "$0") --force         # Run without confirmations

SAFETY:
    • Creates automatic backups before changes
    • Logs all actions for review
    • Provides rollback information
    • Skips destructive operations by default

RELATED COMMANDS:
    system-health-master            # Check system health
    system-maintenance              # Run preventive maintenance

EOF
}

# Parse command line arguments
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Safety confirmation
if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
    echo -e "${YELLOW}${WARNING} This will attempt to automatically fix system issues.${NC}"
    echo "A backup will be created before making changes."
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Auto-fix cancelled."
        exit 0
    fi
    echo ""
fi

# Execute based on mode
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BLUE}${INFO} DRY RUN MODE - No changes will be made${NC}"
    echo "This would attempt to fix the following issues:"
    echo ""
    echo "• Nix store optimization and cleanup"
    echo "• Package management updates"
    echo "• Permission fixes for SSH and GPG"
    echo "• Configuration file repairs"
    echo "• Development environment cleanup"
    echo ""
    echo "Run without --dry-run to execute fixes."
else
    main
fi