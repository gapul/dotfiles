#!/usr/bin/env bash

# Master Health Check System for Dotfiles
# Provides comprehensive health monitoring, automatic fixes, and maintenance

set -euo pipefail

# Colors and icons
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Icons
CHECK="✅"
CROSS="❌"
WARNING="⚠️"
INFO="ℹ️"
GEAR="⚙️"
ROCKET="🚀"

# Health check results storage
declare -A health_results
health_score=0
total_checks=0

# Log functions
log_header() {
    echo -e "${BLUE}${1}${NC}"
    echo "$(printf '=%.0s' {1..${#1}})"
}

log_success() {
    echo -e "${GREEN}${CHECK} $1${NC}"
}

log_error() {
    echo -e "${RED}${CROSS} $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}${WARNING} $1${NC}"
}

log_info() {
    echo -e "${CYAN}${INFO} $1${NC}"
}

# Health check function
run_health_check() {
    local component="$1"
    local check_command="$2"
    local description="$3"
    
    total_checks=$((total_checks + 1))
    
    printf "Checking %-40s ... " "$description"
    
    if eval "$check_command" &>/dev/null; then
        health_results["$component"]="✅ PASS"
        health_score=$((health_score + 1))
        echo -e "${GREEN}✅${NC}"
        return 0
    else
        health_results["$component"]="❌ FAIL"
        echo -e "${RED}❌${NC}"
        return 1
    fi
}

# Performance check function
check_performance() {
    local metric="$1"
    local command="$2"
    local threshold="$3"
    local description="$4"
    
    total_checks=$((total_checks + 1))
    printf "Checking %-40s ... " "$description"
    
    local value
    value=$(eval "$command" 2>/dev/null || echo "0")
    
    if (( $(echo "$value <= $threshold" | bc -l) )); then
        health_results["perf_$metric"]="✅ PASS ($value)"
        health_score=$((health_score + 1))
        echo -e "${GREEN}✅ ($value)${NC}"
        return 0
    else
        health_results["perf_$metric"]="⚠️ WARNING ($value)"
        echo -e "${YELLOW}⚠️ ($value > $threshold)${NC}"
        return 1
    fi
}

# Main health check execution
main() {
    log_header "🏥 System Health Check - Master Dashboard"
    echo "Started at: $(date)"
    echo ""
    
    # 1. Nix System Health
    log_header "🔧 Nix System Health"
    run_health_check "nix_flake" "nix flake check --no-build" "Nix flake configuration"
    run_health_check "nix_store" "test -d /nix/store" "Nix store availability"
    run_health_check "home_manager" "command -v home-manager" "Home Manager availability"
    if command -v darwin-rebuild &>/dev/null; then
        run_health_check "nix_darwin" "darwin-rebuild --version" "nix-darwin availability"
    fi
    echo ""
    
    # 2. Development Environment
    log_header "💻 Development Environment"
    run_health_check "neovim" "nvim --version" "Neovim installation"
    run_health_check "git" "git --version" "Git installation"
    run_health_check "git_config" "git config --global user.email && git config --global user.name" "Git configuration"
    if command -v docker &>/dev/null; then
        run_health_check "docker" "docker --version" "Docker installation"
    fi
    if command -v node &>/dev/null; then
        run_health_check "node" "node --version" "Node.js installation"
    fi
    echo ""
    
    # 3. Modern CLI Tools
    log_header "🛠️ Modern CLI Tools"
    local cli_tools=("eza" "bat" "rg" "fd" "zoxide" "lazygit" "yazi" "btm")
    for tool in "${cli_tools[@]}"; do
        run_health_check "cli_$tool" "command -v $tool" "$tool (modern CLI)"
    done
    echo ""
    
    # 4. AI Platform
    log_header "🤖 AI Platform"
    if command -v ollama &>/dev/null; then
        run_health_check "ollama" "ollama --version" "Ollama LLM platform"
        run_health_check "ollama_models" "ollama list | grep -q ." "Ollama models available"
    fi
    if command -v gh &>/dev/null; then
        run_health_check "gh_copilot" "gh extension list | grep -q copilot" "GitHub Copilot CLI"
    fi
    echo ""
    
    # 5. Phase 6 QoL Tools
    log_header "✨ Phase 6 QoL Tools"
    local qol_tools=("fastfetch" "nom" "nix-tree")
    for tool in "${qol_tools[@]}"; do
        run_health_check "qol_$tool" "command -v $tool" "$tool"
    done
    echo ""
    
    # 6. Security
    log_header "🔒 Security"
    run_health_check "ssh_config" "test -f ~/.ssh/config" "SSH configuration"
    run_health_check "ssh_permissions" "test \$(stat -f '%A' ~/.ssh 2>/dev/null || echo '000') = '700'" "SSH directory permissions"
    if command -v sops &>/dev/null; then
        run_health_check "sops" "sops --version" "SOPS encryption tool"
    fi
    if command -v age &>/dev/null; then
        run_health_check "age" "age --version" "age encryption"
    fi
    if command -v gpg &>/dev/null; then
        run_health_check "gpg" "gpg --list-secret-keys" "GPG keys configured"
    fi
    echo ""
    
    # 7. System Resources
    log_header "📊 System Resources"
    
    # Disk space check (macOS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        check_performance "disk_usage" "df -h / | awk 'NR==2 {print \$5}' | sed 's/%//'" "90" "Disk space usage (< 90%)"
        
        # Memory check (macOS)
        local memory_pressure
        memory_pressure=$(memory_pressure | grep "System-wide memory free percentage" | awk '{print $5}' | sed 's/%//' || echo "50")
        local memory_used=$((100 - memory_pressure))
        check_performance "memory_usage" "echo $memory_used" "90" "Memory usage (< 90%)"
    fi
    
    # Check Nix store size
    if [[ -d "/nix/store" ]]; then
        local store_size_gb
        store_size_gb=$(du -sg /nix/store 2>/dev/null | cut -f1)
        if [[ $store_size_gb -gt 50 ]]; then
            health_results["nix_store_size"]="⚠️ WARNING (${store_size_gb}GB)"
            log_warning "Nix store size: ${store_size_gb}GB (consider garbage collection)"
        else
            health_results["nix_store_size"]="✅ PASS (${store_size_gb}GB)"
            log_success "Nix store size: ${store_size_gb}GB"
        fi
        total_checks=$((total_checks + 1))
    fi
    echo ""
    
    # 8. Configuration Files
    log_header "⚙️ Configuration Files"
    local config_files=(
        "$HOME/.zshrc:Zsh configuration"
        "$HOME/.config/nvim/init.lua:Neovim configuration"
        "$HOME/.config/git/config:Git configuration"
        "$HOME/.config/starship.toml:Starship prompt"
    )
    
    for config_entry in "${config_files[@]}"; do
        local file_path="${config_entry%:*}"
        local file_desc="${config_entry#*:}"
        run_health_check "config_$(basename "$file_path")" "test -f '$file_path'" "$file_desc"
    done
    echo ""
    
    # Results Summary
    echo ""
    log_header "📋 Health Check Summary"
    
    local health_percentage=$((health_score * 100 / total_checks))
    
    echo "Overall Health Score: $health_score/$total_checks ($health_percentage%)"
    echo ""
    
    # Detailed results
    echo "Component Status:"
    for component in "${!health_results[@]}"; do
        echo "  $component: ${health_results[$component]}"
    done
    echo ""
    
    # Overall assessment
    if [ $health_percentage -ge 95 ]; then
        log_success "System health is EXCELLENT! 🎉"
        echo "Your dotfiles system is running optimally."
    elif [ $health_percentage -ge 80 ]; then
        log_info "System health is GOOD. Some minor issues detected."
        echo "Most components are working well with minor issues."
    elif [ $health_percentage -ge 60 ]; then
        log_warning "System health is FAIR. Several issues need attention."
        echo "Multiple components need attention for optimal performance."
    else
        log_error "System health is POOR. Immediate action required!"
        echo "Critical issues detected that may impact functionality."
    fi
    
    # Recommended actions
    if [ $health_percentage -lt 100 ]; then
        echo ""
        log_header "🔧 Recommended Actions"
        
        if [[ "${health_results[nix_store_size]:-}" == *"WARNING"* ]]; then
            echo "• Run 'nix-collect-garbage -d' to clean Nix store"
        fi
        
        local failed_components=()
        for component in "${!health_results[@]}"; do
            if [[ "${health_results[$component]}" == *"FAIL"* ]]; then
                failed_components+=("$component")
            fi
        done
        
        if [[ ${#failed_components[@]} -gt 0 ]]; then
            echo "• Run 'system-auto-fix' to attempt automatic repairs"
            echo "• Failed components: ${failed_components[*]}"
        fi
        
        echo "• Run 'system-maintenance' for preventive maintenance"
        echo "• Check individual component health with specific commands"
        echo "• Consider 'just rebuild' to refresh configuration"
    fi
    
    # Save detailed log
    local log_dir="$HOME/.dotfiles-health"
    local log_file="$log_dir/health-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$log_dir"
    
    {
        echo "Dotfiles Health Check Report"
        echo "Generated: $(date)"
        echo "================================"
        echo "Score: $health_score/$total_checks ($health_percentage%)"
        echo ""
        echo "Component Results:"
        for component in "${!health_results[@]}"; do
            echo "$component: ${health_results[$component]}"
        done
        echo ""
        echo "System Information:"
        echo "OS: $(uname -s) $(uname -r)"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "macOS: $(sw_vers -productVersion)"
        fi
        if command -v nix &>/dev/null; then
            echo "Nix: $(nix --version | head -1)"
        fi
    } > "$log_file"
    
    log_info "Detailed report saved to: $log_file"
    
    # Return appropriate exit code
    if [ $health_percentage -ge 80 ]; then
        return 0
    else
        return 1
    fi
}

# Help function
show_help() {
    cat << EOF
System Health Check - Master Dashboard

USAGE:
    $(basename "$0") [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    -q, --quiet     Run in quiet mode (less verbose output)
    -v, --verbose   Run in verbose mode (more detailed output)
    --json          Output results in JSON format

EXAMPLES:
    $(basename "$0")                 # Run full health check
    $(basename "$0") --quiet         # Run with minimal output
    $(basename "$0") --json         # Get JSON results for automation

RELATED COMMANDS:
    system-auto-fix                 # Attempt automatic repairs
    system-maintenance              # Run preventive maintenance
    performance-monitor             # Monitor system performance
    health-dashboard                # Generate HTML dashboard

EOF
}

# Parse command line arguments
QUIET=false
VERBOSE=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
if [[ "$JSON_OUTPUT" == "true" ]]; then
    # JSON output mode for automation
    main >/dev/null 2>&1
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"health_score\": $health_score,"
        echo "  \"total_checks\": $total_checks,"
        echo "  \"health_percentage\": $((health_score * 100 / total_checks)),"
        echo "  \"components\": {"
        local first=true
        for component in "${!health_results[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            local status="${health_results[$component]}"
            local json_status
            if [[ "$status" == *"PASS"* ]]; then
                json_status="pass"
            elif [[ "$status" == *"FAIL"* ]]; then
                json_status="fail"
            else
                json_status="warning"
            fi
            echo -n "    \"$component\": {\"status\": \"$json_status\", \"message\": \"$status\"}"
        done
        echo ""
        echo "  }"
        echo "}"
    }
else
    main
fi