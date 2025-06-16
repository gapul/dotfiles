#!/bin/bash

# Intelligent Package Analysis and Recommendations
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Analyze package usage patterns
analyze_usage_patterns() {
    log_info "=== Package Usage Pattern Analysis ==="
    
    local usage_file="$HOME/.dotfiles/package-usage.log"
    mkdir -p "$(dirname "$usage_file")"
    
    # Track command usage
    if [[ -f "$HOME/.zsh_history" ]]; then
        # Extract most used commands
        log_info "Most frequently used commands:"
        sed 's/^: [0-9]*:[0-9]*;//' "$HOME/.zsh_history" | \
            awk '{print $1}' | \
            sort | uniq -c | sort -nr | head -20 | \
            while read -r count cmd; do
                printf "  %3d: %s\n" "$count" "$cmd"
            done
    fi
    
    echo ""
    
    # Suggest package optimizations
    log_info "Package optimization suggestions:"
    
    # Check for unused packages
    local darwin_packages
    darwin_packages=$(nix eval --json ".#darwinConfigurations.yuki.config.environment.systemPackages" --file "$DOTFILES_DIR/nix/flake.nix" 2>/dev/null | jq -r '.[]' | sort | uniq)
    
    echo "📦 Currently managed packages: $(echo "$darwin_packages" | wc -l | tr -d ' ')"
    
    # Suggest missing common tools
    local common_tools=(
        "htop" "btop" "neofetch" "tree" "jq" "ripgrep" "fd" "bat" "eza"
        "zoxide" "starship" "tmux" "git" "gh" "curl" "wget" "vim" "neovim"
    )
    
    log_info "Checking for missing common development tools:"
    for tool in "${common_tools[@]}"; do
        if ! echo "$darwin_packages" | grep -q "^$tool$"; then
            if command -v "$tool" >/dev/null 2>&1; then
                log_success "✓ $tool (available but not in nix config)"
            else
                log_warning "⚠ $tool (missing - consider adding to nix)"
            fi
        else
            log_success "✓ $tool (managed by nix)"
        fi
    done
}

# Recommend system improvements
recommend_improvements() {
    log_info "=== System Improvement Recommendations ==="
    
    # Check system performance
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    
    if (( $(echo "$load_avg > 2.0" | bc -l) )); then
        log_warning "High system load detected ($load_avg) - consider:"
        echo "  • Reducing parallel build jobs in nix"
        echo "  • Adding more swap space"
        echo "  • Investigating background processes"
    else
        log_success "System load is healthy ($load_avg)"
    fi
    
    # Check disk space
    local disk_usage
    disk_usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    
    if (( disk_usage > 85 )); then
        log_warning "Disk usage high (${disk_usage}%) - consider:"
        echo "  • Running 'nix store gc --older-than 30d'"
        echo "  • Running 'nix store optimise'"
        echo "  • Cleaning up old backups"
    else
        log_success "Disk usage is healthy (${disk_usage}%)"
    fi
    
    # Check nix store size
    local store_size
    if command -v nix >/dev/null 2>&1; then
        store_size=$(nix path-info --closure-size --human-readable nixpkgs#hello 2>/dev/null | head -1 || echo "Unknown")
        log_info "Nix store health: $store_size typical package closure"
    fi
}

# Generate optimization report
generate_report() {
    local report_file="$HOME/.dotfiles/optimization-report-$(date +%Y%m%d_%H%M%S).md"
    
    {
        echo "# System Optimization Report"
        echo "Generated: $(date)"
        echo ""
        
        echo "## System Status"
        echo "- Load Average: $(uptime | awk -F'load average:' '{print $2}')"
        echo "- Disk Usage: $(df -h / | tail -1 | awk '{print $5}')"
        echo "- Memory: $(vm_stat | grep 'Pages free' | awk '{print $3 * 4096 / 1024 / 1024 " MB free"}')"
        echo ""
        
        echo "## Nix Configuration"
        if [[ -f /etc/nix/nix.conf ]]; then
            echo "- Nix configuration: Optimized"
            echo "- Build parallelism: $(grep 'max-jobs' /etc/nix/nix.conf || echo 'Default')"
        else
            echo "- Nix configuration: Default (consider optimization)"
        fi
        echo ""
        
        echo "## Automation Status"
        if launchctl list | grep -q "com.dotfiles.maintenance"; then
            echo "- ✅ Automated maintenance: Enabled"
        else
            echo "- ❌ Automated maintenance: Disabled"
        fi
        
        if launchctl list | grep -q "com.dotfiles.security-updates"; then
            echo "- ✅ Security updates: Enabled"
        else
            echo "- ❌ Security updates: Disabled"
        fi
        
    } > "$report_file"
    
    log_success "Optimization report saved: $report_file"
}

# Main execution
main() {
    case "${1:-analyze}" in
        "analyze")
            analyze_usage_patterns
            echo ""
            recommend_improvements
            echo ""
            generate_report
            ;;
        "usage")
            analyze_usage_patterns
            ;;
        "recommendations")
            recommend_improvements
            ;;
        "report")
            generate_report
            ;;
        *)
            echo "Usage: $0 {analyze|usage|recommendations|report}"
            echo ""
            echo "Commands:"
            echo "  analyze         - Full analysis and report generation"
            echo "  usage          - Analyze package usage patterns"
            echo "  recommendations - System improvement recommendations"
            echo "  report         - Generate optimization report"
            exit 1
            ;;
    esac
}

main "$@"
