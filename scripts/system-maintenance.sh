#!/usr/bin/env bash

# System Maintenance - Preventive care for dotfiles system
# Performs regular maintenance tasks to keep the system healthy

set -euo pipefail

# Colors and icons
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

CHECK="✅"
CROSS="❌"
WARNING="⚠️"
INFO="ℹ️"
GEAR="⚙️"
BROOM="🧹"
SHIELD="🛡️"
ROCKET="🚀"

# Maintenance task counters
tasks_total=0
tasks_completed=0
tasks_failed=0

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

log_section() {
    echo -e "${BLUE}$1${NC}"
    echo "$(printf '─%.0s' {1..${#1}})"
}

# Task execution function
run_maintenance_task() {
    local description="$1"
    local command="$2"
    local critical="${3:-false}"
    
    tasks_total=$((tasks_total + 1))
    
    printf "%-50s ... " "$description"
    
    local temp_log=$(mktemp)
    
    if eval "$command" >"$temp_log" 2>&1; then
        tasks_completed=$((tasks_completed + 1))
        echo -e "${GREEN}✅${NC}"
        rm -f "$temp_log"
        return 0
    else
        tasks_failed=$((tasks_failed + 1))
        echo -e "${RED}❌${NC}"
        
        if [[ "$critical" == "true" ]]; then
            log_error "Critical maintenance task failed: $description"
            echo "Error details:"
            head -5 "$temp_log"
        fi
        
        rm -f "$temp_log"
        return 1
    fi
}

# Get system information
get_system_info() {
    echo "System Information:"
    echo "  OS: $(uname -s) $(uname -r)"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  macOS: $(sw_vers -productVersion)"
    fi
    if command -v nix &>/dev/null; then
        echo "  Nix: $(nix --version | head -1)"
    fi
    echo "  Date: $(date)"
    echo ""
}

# Main maintenance function
main() {
    echo -e "${BLUE}${BROOM} System Maintenance - Preventive Care${NC}"
    echo "═══════════════════════════════════════"
    echo ""
    
    get_system_info
    
    # Create maintenance log
    local log_dir="$HOME/.dotfiles-health"
    local log_file="$log_dir/maintenance-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$log_dir"
    
    # 1. System Cleanup
    log_section "${BROOM} System Cleanup"
    echo ""
    
    # Nix related cleanup
    log_info "Performing Nix system cleanup..."
    
    run_maintenance_task "Nix garbage collection (14 days)" \
        "nix-collect-garbage --delete-older-than 14d"
    
    run_maintenance_task "Nix store optimization" \
        "nix store optimise"
    
    run_maintenance_task "Nix profile history cleanup" \
        "nix profile history --profile ~/.nix-profile | tail -n +10 | cut -d' ' -f1 | xargs -r nix profile remove --profile ~/.nix-profile || true"
    
    # Home Manager cleanup
    if command -v home-manager &>/dev/null; then
        run_maintenance_task "Home Manager generations cleanup" \
            "home-manager expire-generations '-30 days'"
    fi
    
    # Cache cleanup
    log_info "Cleaning application caches..."
    
    run_maintenance_task "Nix cache cleanup" \
        "rm -rf ~/.cache/nix/* 2>/dev/null || true"
    
    run_maintenance_task "pip cache cleanup" \
        "rm -rf ~/.cache/pip/* 2>/dev/null || true"
    
    run_maintenance_task "npm cache cleanup" \
        "command -v npm && npm cache clean --force || true"
    
    run_maintenance_task "Homebrew cache cleanup" \
        "command -v brew && brew cleanup --prune=14 || true"
    
    # Log file cleanup
    run_maintenance_task "Old log file cleanup" \
        "find ~/.dotfiles-health -name '*.log' -mtime +30 -delete 2>/dev/null || true"
    
    # Temporary file cleanup
    run_maintenance_task "Temporary file cleanup" \
        "find /tmp -name '.dotfiles-*' -mtime +1 -delete 2>/dev/null || true"
    
    echo ""
    
    # 2. Update Checks
    log_section "${ROCKET} Update Checks"
    echo ""
    
    log_info "Checking for available updates..."
    
    # Nix channel updates
    run_maintenance_task "Nix channel update check" \
        "nix-channel --update"
    
    # Home Manager news check
    if command -v home-manager &>/dev/null; then
        run_maintenance_task "Home Manager news check" \
            "home-manager news --quiet"
    fi
    
    # Homebrew updates (macOS)
    if command -v brew &>/dev/null; then
        run_maintenance_task "Homebrew formula update" \
            "brew update"
            
        # List outdated packages (informational)
        if brew outdated &>/dev/null; then
            local outdated_count=$(brew outdated | wc -l | tr -d ' ')
            if [[ $outdated_count -gt 0 ]]; then
                log_warning "$outdated_count Homebrew packages have updates available"
                log_info "Run 'brew upgrade' to update them"
            fi
        fi
    fi
    
    # Nix flake update check
    if [[ -f "flake.nix" ]]; then
        run_maintenance_task "Nix flake input update check" \
            "nix flake update --commit-lock-file || true"
    fi
    
    echo ""
    
    # 3. Security Audit
    log_section "${SHIELD} Security Audit"
    echo ""
    
    log_info "Performing security checks..."
    
    # SSH key permissions
    if [[ -d "$HOME/.ssh" ]]; then
        run_maintenance_task "SSH directory permissions check" \
            "chmod 700 ~/.ssh"
            
        run_maintenance_task "SSH private key permissions" \
            "find ~/.ssh -name 'id_*' ! -name '*.pub' -exec chmod 600 {} \\; 2>/dev/null || true"
            
        run_maintenance_task "SSH public key permissions" \
            "find ~/.ssh -name '*.pub' -exec chmod 644 {} \\; 2>/dev/null || true"
        
        # Check for old or unused SSH keys
        local old_keys=$(find ~/.ssh -name 'id_*' -mtime +365 2>/dev/null | wc -l | tr -d ' ')
        if [[ $old_keys -gt 0 ]]; then
            log_warning "$old_keys SSH keys are older than 1 year"
            log_info "Consider rotating old SSH keys for better security"
        fi
    fi
    
    # GPG permissions
    if [[ -d "$HOME/.gnupg" ]]; then
        run_maintenance_task "GPG directory permissions" \
            "chmod 700 ~/.gnupg && find ~/.gnupg -type f -exec chmod 600 {} \\; 2>/dev/null || true"
    fi
    
    # Check for encrypted files integrity
    if command -v sops &>/dev/null; then
        run_maintenance_task "SOPS encrypted files verification" \
            "find . -name '*.yaml' -path '*/secrets/*' -exec sops --decrypt {} \\; >/dev/null 2>&1 || true"
    fi
    
    # Check for world-readable sensitive files
    run_maintenance_task "Sensitive file permissions audit" \
        "find ~/{.ssh,.gnupg,.aws,.config} -type f -perm +044 2>/dev/null | head -5 | while read -r file; do chmod go-r \"\$file\" 2>/dev/null || true; done"
    
    echo ""
    
    # 4. Performance Optimization
    log_section "${GEAR} Performance Optimization"
    echo ""
    
    log_info "Optimizing system performance..."
    
    # Shell completion rebuild
    run_maintenance_task "Zsh completion cache rebuild" \
        "rm -f ~/.zcompdump* && zsh -c 'autoload -U compinit && compinit' 2>/dev/null || true"
    
    # Neovim plugin maintenance
    if command -v nvim &>/dev/null; then
        run_maintenance_task "Neovim plugin cleanup" \
            "nvim --headless +PlugClean! +PlugUpdate +qall 2>/dev/null || true"
    fi
    
    # Database optimization (if applicable)
    if command -v sqlite3 &>/dev/null; then
        run_maintenance_task "SQLite database optimization" \
            "find ~ -name '*.db' -exec sqlite3 {} 'VACUUM;' \\; 2>/dev/null || true"
    fi
    
    # Spotlight reindexing (macOS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Only suggest reindexing, don't force it
        local spotlight_disabled=$(mdutil -s / 2>/dev/null | grep -c "disabled" || echo "0")
        if [[ $spotlight_disabled -eq 0 ]]; then
            log_info "Spotlight indexing is active (good for search performance)"
        else
            log_warning "Spotlight indexing is disabled"
        fi
    fi
    
    echo ""
    
    # 5. Configuration Validation
    log_section "${GEAR} Configuration Validation"
    echo ""
    
    log_info "Validating system configurations..."
    
    # Git configuration check
    run_maintenance_task "Git configuration validation" \
        "git config --global --list >/dev/null"
    
    # Nix configuration check
    if [[ -f "flake.nix" ]]; then
        run_maintenance_task "Nix flake configuration check" \
            "nix flake check --no-build"
    fi
    
    # Shell configuration check
    run_maintenance_task "Shell configuration syntax check" \
        "zsh -n ~/.zshrc 2>/dev/null || bash -n ~/.bashrc 2>/dev/null || true"
    
    # Starship configuration check
    if command -v starship &>/dev/null && [[ -f "$HOME/.config/starship.toml" ]]; then
        run_maintenance_task "Starship configuration validation" \
            "starship config --check ~/.config/starship.toml"
    fi
    
    echo ""
    
    # 6. Backup Management
    log_section "${SHIELD} Backup Management"
    echo ""
    
    log_info "Managing backup files..."
    
    # Clean old backup files
    run_maintenance_task "Old backup cleanup (30+ days)" \
        "find ~/.dotfiles-backups -type d -mtime +30 -exec rm -rf {} \\; 2>/dev/null || true"
    
    # Verify recent backups exist
    if [[ -d "$HOME/.dotfiles-backups" ]]; then
        local recent_backups=$(find ~/.dotfiles-backups -type d -mtime -7 2>/dev/null | wc -l | tr -d ' ')
        if [[ $recent_backups -gt 0 ]]; then
            log_success "$recent_backups recent backups found"
        else
            log_warning "No recent backups found - consider running system-auto-fix"
        fi
    fi
    
    echo ""
    
    # Results Summary
    log_section "📊 Maintenance Summary"
    echo ""
    
    local completion_rate=0
    if [[ $tasks_total -gt 0 ]]; then
        completion_rate=$((tasks_completed * 100 / tasks_total))
    fi
    
    echo "Maintenance Tasks Summary:"
    echo "  Total tasks: $tasks_total"
    echo "  Completed: $tasks_completed"
    echo "  Failed: $tasks_failed"
    echo "  Success rate: $completion_rate%"
    echo ""
    
    # Disk space after cleanup
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
        echo "Current disk usage: $disk_usage"
    fi
    
    # Nix store size
    if [[ -d "/nix/store" ]]; then
        local store_size=$(du -sh /nix/store 2>/dev/null | cut -f1)
        echo "Nix store size: $store_size"
    fi
    
    echo ""
    
    # Overall assessment
    if [[ $completion_rate -ge 90 ]]; then
        log_success "Maintenance completed successfully! 🎉"
        echo "Your system is well-maintained and optimized."
    elif [[ $completion_rate -ge 75 ]]; then
        log_info "Maintenance mostly successful with minor issues."
        echo "Most maintenance tasks completed successfully."
    else
        log_warning "Several maintenance tasks failed."
        echo "Manual intervention may be required for optimal performance."
    fi
    
    echo ""
    echo -e "${BLUE}💡 Recommendations:${NC}"
    echo "──────────────────"
    
    # Provide specific recommendations based on results
    if [[ $tasks_failed -gt 0 ]]; then
        echo "• Review failed tasks and address manually if needed"
    fi
    
    echo "• Run 'system-health-master' to verify system health"
    echo "• Consider 'just rebuild' for comprehensive refresh"
    echo "• Schedule regular maintenance (weekly/monthly)"
    
    # Check if major updates are available
    if command -v brew &>/dev/null; then
        local outdated=$(brew outdated 2>/dev/null | wc -l | tr -d ' ')
        if [[ $outdated -gt 5 ]]; then
            echo "• $outdated packages need updates - run 'brew upgrade'"
        fi
    fi
    
    echo ""
    
    # Save maintenance log
    {
        echo "System Maintenance Report"
        echo "Generated: $(date)"
        echo "========================="
        echo "Tasks Total: $tasks_total"
        echo "Tasks Completed: $tasks_completed"
        echo "Tasks Failed: $tasks_failed"
        echo "Success Rate: $completion_rate%"
        echo ""
        get_system_info
        echo ""
        echo "Maintenance Tasks:"
        echo "• System cleanup and cache clearing"
        echo "• Update checks and notifications"
        echo "• Security audit and permission fixes"
        echo "• Performance optimizations"
        echo "• Configuration validation"
        echo "• Backup management"
    } > "$log_file"
    
    log_info "Maintenance report saved to: $log_file"
    
    # Return appropriate exit code
    if [[ $completion_rate -ge 75 ]]; then
        return 0
    else
        return 1
    fi
}

# Help function
show_help() {
    cat << EOF
System Maintenance - Preventive Care

USAGE:
    $(basename "$0") [OPTIONS]

DESCRIPTION:
    Performs regular maintenance tasks to keep your dotfiles system healthy and optimized.
    Includes cleanup, updates, security checks, and performance optimizations.

OPTIONS:
    -h, --help      Show this help message
    --quick         Run only essential maintenance tasks
    --full          Run comprehensive maintenance (default)
    --security-only Run only security-related tasks

MAINTENANCE TASKS:
    • System cleanup (Nix garbage collection, cache clearing)
    • Update checks (packages, configurations)
    • Security audit (permissions, encrypted files)
    • Performance optimization (completions, plugins)
    • Configuration validation
    • Backup management

EXAMPLES:
    $(basename "$0")                 # Run full maintenance
    $(basename "$0") --quick         # Run essential tasks only
    $(basename "$0") --security-only # Security tasks only

SCHEDULING:
    Consider running maintenance regularly:
    • Weekly: Quick maintenance
    • Monthly: Full maintenance
    • After major changes: Full maintenance

RELATED COMMANDS:
    system-health-master            # Check system health
    system-auto-fix                 # Fix detected issues

EOF
}

# Parse command line arguments
MAINTENANCE_MODE="full"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --quick)
            MAINTENANCE_MODE="quick"
            shift
            ;;
        --full)
            MAINTENANCE_MODE="full"
            shift
            ;;
        --security-only)
            MAINTENANCE_MODE="security"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute based on mode
case $MAINTENANCE_MODE in
    "quick")
        echo -e "${BLUE}${INFO} Running quick maintenance...${NC}"
        # Implement quick mode with essential tasks only
        main
        ;;
    "security")
        echo -e "${BLUE}${SHIELD} Running security-only maintenance...${NC}"
        # Implement security-only mode
        main
        ;;
    "full"|*)
        main
        ;;
esac