#!/bin/bash

# System Analyzer - Unified package and application analysis tool
# This script consolidates functionality from multiple analysis scripts:
# - nix-package-optimizer.sh: Package optimization analysis
# - package-intelligence.sh: Usage pattern analysis  
# - discover-unmanaged-apps.sh: Application discovery

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration
readonly DOTFILES_DIR="$(get_dotfiles_dir)"
readonly NIX_DIR="$DOTFILES_DIR/nix"
readonly REPORT_DIR="$DOTFILES_DIR/reports"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create reports directory
mkdir -p "$REPORT_DIR"

# Usage information
show_usage() {
    cat << EOF
使用方法: $0 <command> [options]

COMMANDS:
  package-optimize     Nixパッケージ設定の最適化分析
  discover-apps       未管理アプリケーションの検出
  usage-patterns      パッケージ使用パターンの分析
  full-analysis       完全システム分析（全コマンド実行）
  
OPTIONS:
  --output-dir DIR    レポート出力ディレクトリ（デフォルト: reports/）
  --format FORMAT     出力形式（markdown|json、デフォルト: markdown）
  --verbose           詳細出力
  -h, --help          このヘルプを表示

EXAMPLES:
  $0 package-optimize              # パッケージ最適化分析
  $0 discover-apps --verbose       # アプリ検出（詳細出力）
  $0 full-analysis                 # 完全分析
  $0 usage-patterns --format json  # 使用パターン（JSON出力）

EOF
}

# Package optimization analysis (from nix-package-optimizer.sh)
analyze_package_optimization() {
    log_info "=== パッケージ最適化分析 ==="
    
    local report_file="$REPORT_DIR/package-optimization-$TIMESTAMP.md"
    local verbose_mode="${VERBOSE:-false}"
    
    cat > "$report_file" << EOF
# Package Optimization Analysis Report
Generated: $(date)

## Current Nix Package Configuration

EOF

    # Analyze home.nix packages
    if [[ -f "$NIX_DIR/home.nix" ]]; then
        echo "### Home Manager Packages" >> "$report_file"
        echo "" >> "$report_file"
        
        local package_count=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+)[[:space:]]*$ ]]; then
                local package_name="${BASH_REMATCH[1]}"
                echo "- $package_name" >> "$report_file"
                package_count=$((package_count + 1))
                
                if [[ "$verbose_mode" == "true" ]]; then
                    log_info "Found package: $package_name"
                fi
            fi
        done < <(sed -n '/home\.packages.*with pkgs;/,/\];/p' "$NIX_DIR/home.nix" | grep -E '^\s*[a-zA-Z0-9_-]+\s*$' || true)
        
        echo "" >> "$report_file"
        echo "**Total packages: $package_count**" >> "$report_file"
        echo "" >> "$report_file"
    fi
    
    # Check for package conflicts
    echo "### Potential Optimizations" >> "$report_file"
    echo "" >> "$report_file"
    
    # Check for common duplications
    local optimization_suggestions=()
    
    if command -v brew >/dev/null 2>&1; then
        local brew_packages
        brew_packages=$(brew list --formula 2>/dev/null || true)
        
        if [[ -n "$brew_packages" ]]; then
            optimization_suggestions+=("Consider migrating remaining Homebrew packages to Nix for unified management")
            echo "- Found $(echo "$brew_packages" | wc -l | tr -d ' ') Homebrew packages that could be migrated to Nix" >> "$report_file"
        fi
    fi
    
    # Check system applications
    local system_apps
    system_apps=$(find /Applications -name "*.app" -maxdepth 1 | wc -l | tr -d ' ')
    optimization_suggestions+=("Audit $system_apps system applications for nix-darwin management")
    echo "- Found $system_apps applications in /Applications that could be managed declaratively" >> "$report_file"
    
    if [[ ${#optimization_suggestions[@]} -eq 0 ]]; then
        echo "- No obvious optimizations found. Configuration looks well-organized!" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "## Analysis Complete" >> "$report_file"
    echo "Report saved to: $report_file" >> "$report_file"
    
    log_success "Package optimization analysis completed: $report_file"
}

# Application discovery analysis (from discover-unmanaged-apps.sh)
analyze_unmanaged_applications() {
    log_info "=== 未管理アプリケーション検出 ==="
    
    local report_file="$REPORT_DIR/unmanaged-apps-$TIMESTAMP.md"
    local verbose_mode="${VERBOSE:-false}"
    
    cat > "$report_file" << EOF
# Unmanaged Applications Discovery Report
Generated: $(date)

## System Applications Analysis

EOF

    # Scan /Applications directory
    echo "### Applications in /Applications" >> "$report_file"
    echo "" >> "$report_file"
    
    local app_count=0
    local nix_manageable=0
    
    # Known nix-manageable applications
    local NIX_APPS=(
        "Firefox" "Google Chrome" "Visual Studio Code" "Discord"
        "Slack" "Spotify" "VLC" "Telegram" "WhatsApp"
        "Docker" "Postman" "TablePlus" "Sequel Pro"
        "iTerm" "Alacritty" "Kitty" "Wezterm"
    )
    
    while IFS= read -r app_path; do
        if [[ -d "$app_path" ]]; then
            local app_name
            app_name=$(basename "$app_path" .app)
            app_count=$((app_count + 1))
            
            # Check if app is nix-manageable
            local is_nix_manageable=false
            for nix_app in "${NIX_APPS[@]}"; do
                if [[ "$app_name" == *"$nix_app"* ]]; then
                    is_nix_manageable=true
                    nix_manageable=$((nix_manageable + 1))
                    break
                fi
            done
            
            if [[ "$is_nix_manageable" == "true" ]]; then
                echo "- 🔄 **$app_name** - Can be managed via nix-darwin" >> "$report_file"
            else
                echo "- 📱 $app_name" >> "$report_file"
            fi
            
            if [[ "$verbose_mode" == "true" ]]; then
                log_info "Found app: $app_name (nix-manageable: $is_nix_manageable)"
            fi
        fi
    done < <(find /Applications -name "*.app" -maxdepth 1 2>/dev/null || true)
    
    echo "" >> "$report_file"
    echo "**Summary:** $app_count total applications, $nix_manageable can be managed via nix-darwin" >> "$report_file"
    echo "" >> "$report_file"
    
    # Homebrew cask check
    if command -v brew >/dev/null 2>&1; then
        echo "### Homebrew Cask Applications" >> "$report_file"
        echo "" >> "$report_file"
        
        local cask_apps
        cask_apps=$(brew list --cask 2>/dev/null || true)
        
        if [[ -n "$cask_apps" ]]; then
            echo "$cask_apps" | while read -r cask; do
                echo "- 🍺 $cask (Homebrew managed)" >> "$report_file"
            done
            echo "" >> "$report_file"
            echo "**Recommendation:** Consider migrating to nix-darwin for unified management" >> "$report_file"
        else
            echo "- No Homebrew cask applications found" >> "$report_file"
        fi
        echo "" >> "$report_file"
    fi
    
    log_success "Unmanaged applications analysis completed: $report_file"
}

# Usage pattern analysis (from package-intelligence.sh)
analyze_usage_patterns() {
    log_info "=== パッケージ使用パターン分析 ==="
    
    local report_file="$REPORT_DIR/usage-patterns-$TIMESTAMP.md"
    local format="${FORMAT:-markdown}"
    
    if [[ "$format" == "json" ]]; then
        report_file="$REPORT_DIR/usage-patterns-$TIMESTAMP.json"
        echo "{" > "$report_file"
        echo '  "generated": "'$(date)'",' >> "$report_file"
        echo '  "analysis": {' >> "$report_file"
    else
        cat > "$report_file" << EOF
# Usage Pattern Analysis Report
Generated: $(date)

## Command Usage Analysis

EOF
    fi
    
    # Analyze shell history
    if [[ -f "$HOME/.zsh_history" ]]; then
        log_info "Analyzing shell command usage..."
        
        local top_commands
        top_commands=$(fc -l 1 2>/dev/null | awk '{print $2}' | sort | uniq -c | sort -rn | head -20 || 
                      grep -o '^[^;]*; *\([^;]*\)' "$HOME/.zsh_history" 2>/dev/null | cut -d';' -f2 | awk '{print $1}' | sort | uniq -c | sort -rn | head -20 || true)
        
        if [[ "$format" == "json" ]]; then
            echo '    "top_commands": [' >> "$report_file"
            echo "$top_commands" | while IFS= read -r line; do
                local count=$(echo "$line" | awk '{print $1}')
                local command=$(echo "$line" | awk '{print $2}')
                echo "      {\"command\": \"$command\", \"count\": $count}," >> "$report_file"
            done
            echo '    ],' >> "$report_file"
        else
            echo "### Most Used Commands" >> "$report_file"
            echo "" >> "$report_file"
            echo "$top_commands" | while IFS= read -r line; do
                local count=$(echo "$line" | awk '{print $1}')
                local command=$(echo "$line" | awk '{print $2}')
                echo "- **$command** (used $count times)" >> "$report_file"
            done
            echo "" >> "$report_file"
        fi
    fi
    
    # Analyze installed vs used packages
    echo "### Package Usage Recommendations" >> "$report_file"
    echo "" >> "$report_file"
    
    # Common development patterns
    local dev_indicators=()
    if command -v node >/dev/null 2>&1; then
        dev_indicators+=("Node.js development detected")
    fi
    if command -v python3 >/dev/null 2>&1; then
        dev_indicators+=("Python development detected")
    fi
    if command -v cargo >/dev/null 2>&1; then
        dev_indicators+=("Rust development detected")
    fi
    if command -v go >/dev/null 2>&1; then
        dev_indicators+=("Go development detected")
    fi
    
    if [[ "$format" == "json" ]]; then
        echo '    "development_environment": [' >> "$report_file"
        for indicator in "${dev_indicators[@]}"; do
            echo "      \"$indicator\"," >> "$report_file"
        done
        echo '    ]' >> "$report_file"
        echo '  }' >> "$report_file"
        echo '}' >> "$report_file"
    else
        for indicator in "${dev_indicators[@]}"; do
            echo "- $indicator" >> "$report_file"
        done
        
        if [[ ${#dev_indicators[@]} -eq 0 ]]; then
            echo "- No specific development patterns detected" >> "$report_file"
        fi
        
        echo "" >> "$report_file"
        echo "## Analysis Complete" >> "$report_file"
        echo "Report saved to: $report_file" >> "$report_file"
    fi
    
    log_success "Usage pattern analysis completed: $report_file"
}

# Full system analysis
run_full_analysis() {
    log_info "=== 完全システム分析実行 ==="
    
    local start_time=$(date +%s)
    
    analyze_package_optimization
    analyze_unmanaged_applications  
    analyze_usage_patterns
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Create summary report
    local summary_file="$REPORT_DIR/analysis-summary-$TIMESTAMP.md"
    cat > "$summary_file" << EOF
# System Analysis Summary
Generated: $(date)
Analysis Duration: ${duration}s

## Reports Generated

- [Package Optimization](./package-optimization-$TIMESTAMP.md)
- [Unmanaged Applications](./unmanaged-apps-$TIMESTAMP.md)  
- [Usage Patterns](./usage-patterns-$TIMESTAMP.md)

## Quick Stats

$(find "$REPORT_DIR" -name "*$TIMESTAMP*" -type f | wc -l | tr -d ' ') reports generated
Total analysis time: ${duration} seconds

## Next Steps

1. Review package optimization recommendations
2. Consider migrating unmanaged applications to nix-darwin
3. Optimize package selection based on usage patterns

EOF
    
    log_success "Full analysis completed! Summary: $summary_file"
    log_info "Generated reports in: $REPORT_DIR"
}

# Parse command line arguments
COMMAND=""
VERBOSE=false
FORMAT="markdown"
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        package-optimize|discover-apps|usage-patterns|full-analysis)
            COMMAND="$1"
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Override report directory if specified
if [[ -n "$OUTPUT_DIR" ]]; then
    REPORT_DIR="$OUTPUT_DIR"
    mkdir -p "$REPORT_DIR"
fi

# Execute command
case "$COMMAND" in
    package-optimize)
        analyze_package_optimization
        ;;
    discover-apps)
        analyze_unmanaged_applications
        ;;
    usage-patterns)
        analyze_usage_patterns
        ;;
    full-analysis)
        run_full_analysis
        ;;
    "")
        log_error "No command specified"
        show_usage
        exit 1
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac