#!/bin/bash
# enhanced-dependency-check.sh - Enhanced dependency analysis and validation

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
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

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly REPORT_DIR="$PROJECT_ROOT/reports"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create reports directory
mkdir -p "$REPORT_DIR"

# Dependency analysis
analyze_nix_dependencies() {
    log_info "=== Nix依存関係分析 ==="
    
    local report_file="$REPORT_DIR/nix-dependencies-$TIMESTAMP.md"
    
    cat > "$report_file" << EOF
# Nix Dependencies Analysis Report
Generated: $(date)

## Flake Status
EOF
    
    if [[ -f "$PROJECT_ROOT/nix/flake.nix" ]]; then
        log_info "Nixフレーク分析中..."
        
        # Check flake syntax
        if cd "$PROJECT_ROOT/nix" && nix flake check --no-build 2>/dev/null; then
            echo "✅ Flake syntax valid" >> "$report_file"
            log_success "Flake構文チェック完了"
        else
            echo "❌ Flake syntax errors detected" >> "$report_file"
            log_error "Flake構文エラー検出"
        fi
        
        # Analyze inputs
        echo "" >> "$report_file"
        echo "## Flake Inputs" >> "$report_file"
        if command -v nix &> /dev/null; then
            cd "$PROJECT_ROOT/nix"
            nix flake metadata --json 2>/dev/null | jq -r '.locks.nodes | to_entries[] | select(.key != "root") | "- \(.key): \(.value.locked.rev // .value.locked.narHash // "unknown")"' >> "$report_file" || echo "- Analysis failed" >> "$report_file"
        fi
        
        # Package count analysis
        echo "" >> "$report_file"
        echo "## Package Statistics" >> "$report_file"
        
        # System packages
        local system_packages
        system_packages=$(grep -c "environment.systemPackages" "$PROJECT_ROOT/nix/darwin.nix" || echo "0")
        echo "- System packages declarations: $system_packages" >> "$report_file"
        
        # Homebrew packages
        local homebrew_casks homebrew_brews
        homebrew_casks=$(grep -A 100 'casks = \[' "$PROJECT_ROOT/nix/darwin.nix" | grep -c '".*"' || echo "0")
        homebrew_brews=$(grep -A 10 'brews = \[' "$PROJECT_ROOT/nix/darwin.nix" | grep -c '".*"' | head -1 || echo "0")
        echo "- Homebrew casks: $homebrew_casks" >> "$report_file"
        echo "- Homebrew brews: $homebrew_brews" >> "$report_file"
        
    else
        echo "❌ No flake.nix found" >> "$report_file"
        log_warning "flake.nixが見つかりません"
    fi
    
    log_success "Nix依存関係分析完了: $report_file"
}

# Script dependency analysis
analyze_script_dependencies() {
    log_info "=== スクリプト依存関係分析 ==="
    
    local report_file="$REPORT_DIR/script-dependencies-$TIMESTAMP.md"
    
    cat > "$report_file" << EOF
# Script Dependencies Analysis Report
Generated: $(date)

## Shell Scripts Analysis
EOF
    
    # Find all shell scripts
    find "$PROJECT_ROOT" -name "*.sh" -type f | while read -r script; do
        local relative_path="${script#$PROJECT_ROOT/}"
        echo "" >> "$report_file"
        echo "### $relative_path" >> "$report_file"
        
        # Check external command dependencies
        echo "**External Commands:**" >> "$report_file"
        grep -E "^\s*(command -v|which|\w+\s+--version)" "$script" | sed 's/^/- /' >> "$report_file" || echo "- None detected" >> "$report_file"
        
        # Check file references
        echo "" >> "$report_file"
        echo "**File References:**" >> "$report_file"
        grep -E '\$\{?[A-Z_]+\}?|/[a-zA-Z0-9_./\${}~-]+' "$script" | grep -v "^#" | head -5 | sed 's/^/- /' >> "$report_file" || echo "- None detected" >> "$report_file"
        
        # Check script permissions
        if [[ -x "$script" ]]; then
            echo "- ✅ Executable" >> "$report_file"
        else
            echo "- ❌ Not executable" >> "$report_file"
        fi
    done
    
    log_success "スクリプト依存関係分析完了: $report_file"
}

# Configuration file analysis
analyze_config_dependencies() {
    log_info "=== 設定ファイル依存関係分析 ==="
    
    local report_file="$REPORT_DIR/config-dependencies-$TIMESTAMP.md"
    
    cat > "$report_file" << EOF
# Configuration Dependencies Analysis Report
Generated: $(date)

## Configuration Files Status
EOF
    
    # Check dotfiles mappings
    if [[ -f "$PROJECT_ROOT/scripts/install.sh" ]]; then
        echo "" >> "$report_file"
        echo "### Dotfiles Mappings" >> "$report_file"
        
        # Extract DOTFILES_LIST from install.sh
        awk '/DOTFILES_LIST=/,/^[^"].*"/ { if ($0 ~ /".*:.*"/) print $0 }' "$PROJECT_ROOT/scripts/install.sh" | \
        sed 's/.*"\([^"]*\)".*/\1/' | \
        while IFS=':' read -r source_path target_path; do
            if [[ -n "$source_path" && -n "$target_path" ]]; then
                local source_file="$PROJECT_ROOT/configs/${source_path#configs/}"
                if [[ -f "$source_file" || -d "$source_file" ]]; then
                    echo "- ✅ $source_path → $target_path" >> "$report_file"
                else
                    echo "- ❌ $source_path → $target_path (missing)" >> "$report_file"
                fi
            fi
        done
    fi
    
    # Check configuration file formats
    echo "" >> "$report_file"
    echo "### Configuration File Validation" >> "$report_file"
    
    # JSON files
    find "$PROJECT_ROOT/configs" -name "*.json" -type f 2>/dev/null | while read -r json_file; do
        local relative_path="${json_file#$PROJECT_ROOT/}"
        if jq empty "$json_file" 2>/dev/null; then
            echo "- ✅ $relative_path (valid JSON)" >> "$report_file"
        else
            echo "- ❌ $relative_path (invalid JSON)" >> "$report_file"
        fi
    done
    
    # TOML files
    find "$PROJECT_ROOT/configs" -name "*.toml" -type f 2>/dev/null | while read -r toml_file; do
        local relative_path="${toml_file#$PROJECT_ROOT/}"
        if python3 -c "import tomli; tomli.load(open('$toml_file', 'rb'))" 2>/dev/null; then
            echo "- ✅ $relative_path (valid TOML)" >> "$report_file"
        else
            echo "- ❌ $relative_path (invalid TOML)" >> "$report_file"
        fi
    done
    
    log_success "設定ファイル依存関係分析完了: $report_file"
}

# Security analysis
analyze_security() {
    log_info "=== セキュリティ分析 ==="
    
    local report_file="$REPORT_DIR/security-analysis-$TIMESTAMP.md"
    
    cat > "$report_file" << EOF
# Security Analysis Report
Generated: $(date)

## Potential Security Issues
EOF
    
    # Check for hardcoded secrets
    echo "" >> "$report_file"
    echo "### Secret Scanning" >> "$report_file"
    
    if grep -r -E "(password|secret|key|token|api_key)" "$PROJECT_ROOT/configs" --include="*.json" --include="*.toml" --include="*.yml" 2>/dev/null; then
        echo "❌ Potential secrets found in configuration files" >> "$report_file"
        log_warning "設定ファイルに機密情報の可能性"
    else
        echo "✅ No obvious secrets found in configurations" >> "$report_file"
        log_success "設定ファイルに明らかな機密情報なし"
    fi
    
    # Check gitignore coverage
    echo "" >> "$report_file"
    echo "### .gitignore Coverage" >> "$report_file"
    
    local security_patterns=("*.key" "*.pem" "*.p12" "*.p8" "*.env" "secrets.*" "private.*")
    for pattern in "${security_patterns[@]}"; do
        if grep -q "$pattern" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
            echo "- ✅ $pattern is ignored" >> "$report_file"
        else
            echo "- ⚠️  $pattern not in .gitignore" >> "$report_file"
        fi
    done
    
    # Check file permissions
    echo "" >> "$report_file"
    echo "### File Permissions" >> "$report_file"
    
    find "$PROJECT_ROOT" -type f \( -name "*.sh" -o -name "*.py" \) | while read -r file; do
        local relative_path="${file#$PROJECT_ROOT/}"
        if [[ -x "$file" ]]; then
            echo "- ✅ $relative_path (executable)" >> "$report_file"
        else
            echo "- ⚠️  $relative_path (not executable)" >> "$report_file"
        fi
    done
    
    log_success "セキュリティ分析完了: $report_file"
}

# Performance analysis
analyze_performance() {
    log_info "=== パフォーマンス分析 ==="
    
    local report_file="$REPORT_DIR/performance-analysis-$TIMESTAMP.md"
    
    cat > "$report_file" << EOF
# Performance Analysis Report
Generated: $(date)

## Script Performance Metrics
EOF
    
    # Time shell script syntax checks
    echo "" >> "$report_file"
    echo "### Script Syntax Check Performance" >> "$report_file"
    
    find "$PROJECT_ROOT" -name "*.sh" -type f | while read -r script; do
        local relative_path="${script#$PROJECT_ROOT/}"
        local check_time
        check_time=$(time (bash -n "$script") 2>&1 | grep real | awk '{print $2}' || echo "unknown")
        echo "- $relative_path: $check_time" >> "$report_file"
    done
    
    # Repository size analysis
    echo "" >> "$report_file"
    echo "### Repository Size Analysis" >> "$report_file"
    
    local total_size
    total_size=$(du -sh "$PROJECT_ROOT" | cut -f1)
    echo "- Total repository size: $total_size" >> "$report_file"
    
    # Largest directories
    echo "- Largest directories:" >> "$report_file"
    du -sh "$PROJECT_ROOT"/{configs,scripts,nix,.git} 2>/dev/null | sort -hr | head -5 | while read -r size dir; do
        local relative_dir="${dir#$PROJECT_ROOT/}"
        echo "  - $relative_dir: $size" >> "$report_file"
    done
    
    log_success "パフォーマンス分析完了: $report_file"
}

# Generate comprehensive report
generate_summary_report() {
    log_info "=== 総合レポート生成 ==="
    
    local summary_file="$REPORT_DIR/dependency-summary-$TIMESTAMP.md"
    
    cat > "$summary_file" << EOF
# Comprehensive Dependency Analysis Summary
Generated: $(date)

## Report Files Generated
- Nix Dependencies: nix-dependencies-$TIMESTAMP.md
- Script Dependencies: script-dependencies-$TIMESTAMP.md
- Configuration Dependencies: config-dependencies-$TIMESTAMP.md
- Security Analysis: security-analysis-$TIMESTAMP.md
- Performance Analysis: performance-analysis-$TIMESTAMP.md

## Quick Health Check
EOF
    
    # Overall health indicators
    local health_score=0
    local total_checks=5
    
    # Check if nix flake is valid
    if [[ -f "$PROJECT_ROOT/nix/flake.nix" ]] && cd "$PROJECT_ROOT/nix" && nix flake check --no-build &>/dev/null; then
        echo "- ✅ Nix flake syntax valid" >> "$summary_file"
        ((health_score++))
    else
        echo "- ❌ Nix flake syntax issues" >> "$summary_file"
    fi
    
    # Check if main scripts are executable
    if [[ -x "$PROJECT_ROOT/install.sh" ]] && [[ -x "$PROJECT_ROOT/scripts/install.sh" ]]; then
        echo "- ✅ Main scripts are executable" >> "$summary_file"
        ((health_score++))
    else
        echo "- ❌ Main scripts permission issues" >> "$summary_file"
    fi
    
    # Check basic configuration files
    if [[ -f "$PROJECT_ROOT/configs/zsh/zshrc" ]] && [[ -f "$PROJECT_ROOT/configs/terminal/starship.toml" ]]; then
        echo "- ✅ Core configuration files present" >> "$summary_file"
        ((health_score++))
    else
        echo "- ❌ Missing core configuration files" >> "$summary_file"
    fi
    
    # Check security basics
    if [[ -f "$PROJECT_ROOT/.gitignore" ]] && grep -q "secrets" "$PROJECT_ROOT/.gitignore"; then
        echo "- ✅ Basic security patterns in .gitignore" >> "$summary_file"
        ((health_score++))
    else
        echo "- ⚠️  Security patterns missing from .gitignore" >> "$summary_file"
    fi
    
    # Check CI configuration
    if [[ -f "$PROJECT_ROOT/.github/workflows/ci.yml" ]]; then
        echo "- ✅ CI configuration present" >> "$summary_file"
        ((health_score++))
    else
        echo "- ❌ Missing CI configuration" >> "$summary_file"
    fi
    
    # Health score
    echo "" >> "$summary_file"
    echo "## Overall Health Score: $health_score/$total_checks" >> "$summary_file"
    
    if [[ $health_score -eq $total_checks ]]; then
        echo "🎉 **Excellent** - All checks passed!" >> "$summary_file"
        log_success "全体の健全性: 優秀 ($health_score/$total_checks)"
    elif [[ $health_score -ge $((total_checks * 3 / 4)) ]]; then
        echo "✅ **Good** - Most checks passed" >> "$summary_file"
        log_success "全体の健全性: 良好 ($health_score/$total_checks)"
    elif [[ $health_score -ge $((total_checks / 2)) ]]; then
        echo "⚠️  **Fair** - Some issues detected" >> "$summary_file"
        log_warning "全体の健全性: 普通 ($health_score/$total_checks)"
    else
        echo "❌ **Poor** - Multiple issues need attention" >> "$summary_file"
        log_error "全体の健全性: 要改善 ($health_score/$total_checks)"
    fi
    
    log_success "総合レポート生成完了: $summary_file"
}

# Main execution
main() {
    local mode="${1:-all}"
    
    log_info "Enhanced Dependency Check開始 (mode: $mode)"
    
    case "$mode" in
        "nix")
            analyze_nix_dependencies
            ;;
        "scripts")
            analyze_script_dependencies
            ;;
        "config")
            analyze_config_dependencies
            ;;
        "security")
            analyze_security
            ;;
        "performance")
            analyze_performance
            ;;
        "all"|*)
            analyze_nix_dependencies
            analyze_script_dependencies
            analyze_config_dependencies
            analyze_security
            analyze_performance
            generate_summary_report
            ;;
    esac
    
    log_success "Enhanced Dependency Check完了"
    log_info "レポートディレクトリ: $REPORT_DIR"
}

# Show usage
if [[ "${1:-}" == "--help" ]]; then
    cat << EOF
Enhanced Dependency Check Tool

使用方法:
    $0 [mode]

Mode options:
    all         全ての分析を実行 (デフォルト)
    nix         Nix依存関係分析のみ
    scripts     スクリプト依存関係分析のみ
    config      設定ファイル分析のみ
    security    セキュリティ分析のみ
    performance パフォーマンス分析のみ

例:
    $0              # 全分析実行
    $0 nix          # Nix分析のみ
    $0 security     # セキュリティ分析のみ

EOF
    exit 0
fi

# Execute main function
main "$@"