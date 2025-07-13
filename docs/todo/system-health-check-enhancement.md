# システム全体の自動ヘルスチェック機能強化 - TODO

**ID**: todo-8  
**優先度**: 中  
**推定時間**: 3-4時間  
**ステータス**: 基本機能完了・強化待ち

## 概要

現在のdotfilesシステムには基本的なヘルスチェック機能があるが、包括的な監視、自動修復、予防的メンテナンス機能の強化が必要。

## 現在の状況

### 既存のヘルスチェック機能
- ✅ `dev-health` - 開発環境チェック
- ✅ `ai-platform-health` - AI機能チェック
- ✅ `modern-cli-health` - Modern CLIツールチェック
- ✅ `nix-qol-health` - Phase 6 QoLツールチェック

### 不足している機能
- ❌ システム全体の統合ヘルスチェック
- ❌ 自動修復機能
- ❌ 予防的メンテナンス
- ❌ パフォーマンス監視
- ❌ セキュリティ監査

## 実装目標

- **統合ヘルスチェック**: 全システムコンポーネントの一元監視
- **自動修復**: 検出された問題の自動解決
- **予防的メンテナンス**: 問題発生前の予防措置
- **パフォーマンス監視**: システムパフォーマンスの継続監視
- **レポート生成**: 詳細な診断レポート作成

## 実装手順

### Phase 1: 統合ヘルスチェックシステム

#### 1. マスターヘルスチェック実装
```bash
#!/usr/bin/env bash
# scripts/system-health-master.sh

set -euo pipefail

# 色とアイコン定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# アイコン
CHECK="✅"
CROSS="❌"
WARNING="⚠️"
INFO="ℹ️"
GEAR="⚙️"
ROCKET="🚀"

# ログ関数
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

# ヘルスチェック結果格納
declare -A health_results
health_score=0
total_checks=0

# ヘルスチェック関数
run_health_check() {
    local component="$1"
    local check_command="$2"
    local description="$3"
    
    total_checks=$((total_checks + 1))
    
    echo -n "Checking $description... "
    
    if eval "$check_command" &>/dev/null; then
        health_results["$component"]="✅ PASS"
        health_score=$((health_score + 1))
        echo -e "${GREEN}✅${NC}"
    else
        health_results["$component"]="❌ FAIL"
        echo -e "${RED}❌${NC}"
    fi
}

# メインヘルスチェック実行
main() {
    log_header "🏥 System Health Check - Master Dashboard"
    echo "Started at: $(date)"
    echo ""
    
    # 1. Nix システムチェック
    log_header "🔧 Nix System Health"
    run_health_check "nix_flake" "nix flake check --no-build" "Nix flake configuration"
    run_health_check "nix_store" "nix store verify --all" "Nix store integrity"
    run_health_check "home_manager" "home-manager --version" "Home Manager availability"
    
    # 2. 開発環境チェック
    log_header "💻 Development Environment"
    run_health_check "neovim" "nvim --version" "Neovim installation"
    run_health_check "git" "git --version" "Git installation"
    run_health_check "docker" "docker --version" "Docker installation"
    run_health_check "node" "node --version" "Node.js installation"
    
    # 3. Modern CLI ツールチェック
    log_header "🛠️ Modern CLI Tools"
    run_health_check "eza" "eza --version" "eza (ls replacement)"
    run_health_check "bat" "bat --version" "bat (cat replacement)"
    run_health_check "ripgrep" "rg --version" "ripgrep (grep replacement)"
    run_health_check "fd" "fd --version" "fd (find replacement)"
    run_health_check "zoxide" "zoxide --version" "zoxide (cd replacement)"
    
    # 4. AI プラットフォームチェック
    log_header "🤖 AI Platform"
    run_health_check "ollama" "ollama --version" "Ollama LLM platform"
    run_health_check "gh_copilot" "gh copilot --version" "GitHub Copilot CLI"
    
    # 5. Phase 6 QoL ツールチェック
    log_header "✨ Phase 6 QoL Tools"
    run_health_check "fastfetch" "fastfetch --version" "fastfetch system info"
    run_health_check "nom" "nom --version" "nix-output-monitor"
    run_health_check "nix_tree" "nix-tree --version" "nix-tree dependency viewer"
    
    # 6. セキュリティチェック
    log_header "🔒 Security"
    run_health_check "sops" "sops --version" "SOPS encryption tool"
    run_health_check "age" "age --version" "age encryption"
    run_health_check "ssh_config" "test -f ~/.ssh/config" "SSH configuration"
    
    # 7. システムリソースチェック
    log_header "📊 System Resources"
    run_health_check "disk_space" "df -h / | awk 'NR==2 {print \$5}' | sed 's/%//' | awk '{exit (\$1 > 90) ? 1 : 0}'" "Disk space (< 90%)"
    run_health_check "memory" "free | awk 'NR==2{printf \"%.2f\", \$3*100/\$2}' | awk '{exit (\$1 > 90) ? 1 : 0}'" "Memory usage (< 90%)"
    
    # 結果サマリー表示
    echo ""
    log_header "📋 Health Check Summary"
    
    health_percentage=$((health_score * 100 / total_checks))
    
    echo "Overall Health Score: $health_score/$total_checks ($health_percentage%)"
    echo ""
    
    # 詳細結果
    for component in "${!health_results[@]}"; do
        echo "  $component: ${health_results[$component]}"
    done
    
    echo ""
    
    # 総合判定
    if [ $health_percentage -ge 95 ]; then
        log_success "System health is EXCELLENT! 🎉"
    elif [ $health_percentage -ge 80 ]; then
        log_info "System health is GOOD. Some minor issues detected."
    elif [ $health_percentage -ge 60 ]; then
        log_warning "System health is FAIR. Several issues need attention."
    else
        log_error "System health is POOR. Immediate action required!"
    fi
    
    # 推奨アクション
    if [ $health_percentage -lt 100 ]; then
        echo ""
        log_header "🔧 Recommended Actions"
        echo "Run 'system-auto-fix' to attempt automatic repairs"
        echo "Run 'system-maintenance' for preventive maintenance"
        echo "Check individual component health with specific commands"
    fi
    
    # ログファイル保存
    log_file="$HOME/.dotfiles-health/health-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$(dirname "$log_file")"
    {
        echo "Health Check Report - $(date)"
        echo "================================"
        echo "Score: $health_score/$total_checks ($health_percentage%)"
        echo ""
        for component in "${!health_results[@]}"; do
            echo "$component: ${health_results[$component]}"
        done
    } > "$log_file"
    
    log_info "Detailed report saved to: $log_file"
}

# スクリプト実行
main "$@"
```

#### 2. 自動修復システム
```bash
#!/usr/bin/env bash
# scripts/system-auto-fix.sh

set -euo pipefail

log_info() {
    echo -e "\033[0;36mℹ️  $1\033[0m"
}

log_success() {
    echo -e "\033[0;32m✅ $1\033[0m"
}

log_warning() {
    echo -e "\033[1;33m⚠️  $1\033[0m"
}

log_error() {
    echo -e "\033[0;31m❌ $1\033[0m"
}

# 修復試行回数カウンター
fixes_attempted=0
fixes_successful=0

attempt_fix() {
    local description="$1"
    local fix_command="$2"
    local verify_command="$3"
    
    fixes_attempted=$((fixes_attempted + 1))
    
    log_info "Attempting to fix: $description"
    
    if eval "$fix_command" &>/dev/null; then
        if eval "$verify_command" &>/dev/null; then
            fixes_successful=$((fixes_successful + 1))
            log_success "Fixed: $description"
            return 0
        else
            log_warning "Fix applied but verification failed: $description"
            return 1
        fi
    else
        log_error "Fix failed: $description"
        return 1
    fi
}

main() {
    echo "🔧 System Auto-Fix - Attempting automatic repairs..."
    echo "=================================================="
    echo ""
    
    # 1. Nix システム修復
    echo "🔧 Nix System Fixes:"
    attempt_fix "Nix store optimization" \
        "nix store optimise" \
        "nix store verify --all"
    
    attempt_fix "Garbage collection" \
        "nix store gc" \
        "test -d /nix/store"
    
    # 2. パッケージ関連修復
    echo ""
    echo "📦 Package Management Fixes:"
    attempt_fix "Home Manager channel update" \
        "nix-channel --update home-manager" \
        "home-manager --version"
    
    attempt_fix "Homebrew update (macOS)" \
        "command -v brew && brew update" \
        "command -v brew && brew --version"
    
    # 3. 開発環境修復
    echo ""
    echo "💻 Development Environment Fixes:"
    attempt_fix "Node.js cache cleanup" \
        "npm cache clean --force" \
        "npm --version"
    
    attempt_fix "Docker system prune" \
        "docker system prune -f" \
        "docker --version"
    
    # 4. 権限修復
    echo ""
    echo "🔒 Permission Fixes:"
    attempt_fix "SSH permissions" \
        "chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_* ~/.ssh/config 2>/dev/null || true" \
        "test -d ~/.ssh"
    
    attempt_fix "GPG permissions" \
        "chmod 700 ~/.gnupg && chmod 600 ~/.gnupg/* 2>/dev/null || true" \
        "test -d ~/.gnupg"
    
    # 5. 設定ファイル修復
    echo ""
    echo "⚙️ Configuration Fixes:"
    attempt_fix "Zsh completion rebuild" \
        "rm -f ~/.zcompdump* && exec zsh" \
        "test -f ~/.zshrc"
    
    attempt_fix "Neovim plugin sync" \
        "nvim --headless +PlugUpdate +qall" \
        "nvim --version"
    
    # 結果サマリー
    echo ""
    echo "📊 Auto-Fix Summary:"
    echo "==================="
    echo "Fixes attempted: $fixes_attempted"
    echo "Fixes successful: $fixes_successful"
    
    success_rate=$((fixes_successful * 100 / fixes_attempted))
    echo "Success rate: $success_rate%"
    
    if [ $success_rate -ge 80 ]; then
        log_success "Auto-fix completed successfully!"
    elif [ $success_rate -ge 50 ]; then
        log_warning "Auto-fix partially successful. Manual intervention may be needed."
    else
        log_error "Auto-fix had limited success. Manual troubleshooting recommended."
    fi
    
    echo ""
    echo "💡 Next steps:"
    echo "- Run 'system-health-master' to verify fixes"
    echo "- Check specific component health if issues persist"
    echo "- Consider manual intervention for complex issues"
}

main "$@"
```

### Phase 2: 予防的メンテナンス

#### 1. 定期メンテナンススクリプト
```bash
#!/usr/bin/env bash
# scripts/system-maintenance.sh

main() {
    echo "🧹 System Maintenance - Preventive Care"
    echo "======================================="
    echo ""
    
    # 1. システムクリーンアップ
    echo "🧹 System Cleanup:"
    
    # Nix関連クリーンアップ
    echo "  • Running Nix garbage collection..."
    nix store gc --max-age 7d
    
    echo "  • Optimizing Nix store..."
    nix store optimise
    
    # キャッシュクリーンアップ
    echo "  • Cleaning application caches..."
    rm -rf ~/.cache/nix
    rm -rf ~/.cache/pip
    rm -rf ~/.npm/_cacache
    
    # 2. 更新チェック
    echo ""
    echo "🔄 Update Checks:"
    
    echo "  • Checking Nix channel updates..."
    nix-channel --update
    
    echo "  • Checking Home Manager updates..."
    home-manager news
    
    # 3. セキュリティ監査
    echo ""
    echo "🔒 Security Audit:"
    
    echo "  • Checking SSH key permissions..."
    find ~/.ssh -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
    find ~/.ssh -type f -name "*.pub" -exec chmod 644 {} \;
    
    echo "  • Verifying encrypted files..."
    if command -v sops &>/dev/null; then
        find nix/secrets -name "*.yaml" -exec sops --decrypt {} \; >/dev/null
    fi
    
    # 4. パフォーマンス最適化
    echo ""
    echo "⚡ Performance Optimization:"
    
    echo "  • Rebuilding shell completions..."
    rm -f ~/.zcompdump*
    
    echo "  • Optimizing Neovim plugins..."
    nvim --headless +PlugClean! +PlugUpdate +qall 2>/dev/null || true
    
    echo ""
    echo "✅ Maintenance completed!"
    echo "💡 Run 'system-health-master' to verify system health"
}

main "$@"
```

### Phase 3: パフォーマンス監視

#### 1. システムパフォーマンス監視
```nix
# nix/common/monitoring/performance.nix
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    # システム監視ツール
    htop
    iotop
    nethogs
    ncdu
    
    # パフォーマンス分析
    hyperfine
    time
  ];

  # パフォーマンス監視スクリプト
  home.file."bin/performance-monitor" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      
      echo "📊 Performance Monitor"
      echo "====================="
      echo ""
      
      # CPU使用率
      echo "🖥️  CPU Usage:"
      top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' | awk '{
        if ($1 > 80) print "❌ High CPU usage: " $1 "%"
        else if ($1 > 60) print "⚠️  Moderate CPU usage: " $1 "%"
        else print "✅ Normal CPU usage: " $1 "%"
      }'
      
      # メモリ使用率
      echo ""
      echo "💾 Memory Usage:"
      vm_stat | awk '
        /Pages free/ {free = $3}
        /Pages active/ {active = $3}
        /Pages inactive/ {inactive = $3}
        /Pages wired/ {wired = $3}
        END {
          total = free + active + inactive + wired
          used_percent = (active + inactive + wired) * 100 / total
          if (used_percent > 90) print "❌ High memory usage: " used_percent "%"
          else if (used_percent > 75) print "⚠️  Moderate memory usage: " used_percent "%"
          else print "✅ Normal memory usage: " used_percent "%"
        }'
      
      # ディスク使用率
      echo ""
      echo "💽 Disk Usage:"
      df -h / | awk 'NR==2 {
        usage = $5
        gsub(/%/, "", usage)
        if (usage > 90) print "❌ High disk usage: " $5
        else if (usage > 75) print "⚠️  Moderate disk usage: " $5
        else print "✅ Normal disk usage: " $5
      }'
      
      # Nix store サイズ
      echo ""
      echo "📦 Nix Store Size:"
      store_size=$(du -sh /nix/store 2>/dev/null | cut -f1)
      echo "Nix store size: $store_size"
      
      # 最近のビルド時間分析
      echo ""
      echo "⏱️  Recent Build Performance:"
      if [ -f ~/.dotfiles-build-times ]; then
        tail -5 ~/.dotfiles-build-times
      else
        echo "No recent build data available"
      fi
    '';
  };
}
```

### Phase 4: レポート生成とダッシュボード

#### 1. HTML ダッシュボード生成
```bash
#!/usr/bin/env bash
# scripts/generate-health-dashboard.sh

generate_html_dashboard() {
    local output_file="$HOME/.dotfiles-health/dashboard.html"
    mkdir -p "$(dirname "$output_file")"
    
    cat > "$output_file" << 'EOF'
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dotfiles System Health Dashboard</title>
    <style>
        body { font-family: 'SF Pro Display', -apple-system, sans-serif; margin: 0; padding: 20px; background: #f5f5f7; }
        .container { max-width: 1200px; margin: 0 auto; }
        .card { background: white; border-radius: 12px; padding: 20px; margin: 20px 0; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #1d1d1f; }
        .status-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px; }
        .status-item { padding: 15px; border-radius: 8px; text-align: center; }
        .status-good { background: #d1f2eb; color: #186a3b; }
        .status-warning { background: #fdeaa7; color: #b7950b; }
        .status-error { background: #fadbd8; color: #a93226; }
        .chart { height: 300px; margin: 20px 0; }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="container">
        <div class="card">
            <h1 class="header">🏥 Dotfiles System Health Dashboard</h1>
            <p class="header">Last updated: <span id="lastUpdated"></span></p>
        </div>
        
        <div class="card">
            <h2>📊 System Overview</h2>
            <div class="status-grid" id="statusGrid">
                <!-- ステータス項目は JavaScript で動的生成 -->
            </div>
        </div>
        
        <div class="card">
            <h2>📈 Performance Metrics</h2>
            <canvas id="performanceChart" class="chart"></canvas>
        </div>
        
        <div class="card">
            <h2>🔄 Recent Activity</h2>
            <div id="recentActivity">
                <!-- 最近のアクティビティログ -->
            </div>
        </div>
    </div>

    <script>
        // データ更新
        document.getElementById('lastUpdated').textContent = new Date().toLocaleString();
        
        // パフォーマンスチャート
        const ctx = document.getElementById('performanceChart').getContext('2d');
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: ['1h ago', '45m ago', '30m ago', '15m ago', 'Now'],
                datasets: [{
                    label: 'CPU Usage (%)',
                    data: [45, 52, 38, 41, 35],
                    borderColor: '#007AFF',
                    tension: 0.4
                }, {
                    label: 'Memory Usage (%)',
                    data: [65, 68, 62, 64, 61],
                    borderColor: '#FF3B30',
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                scales: {
                    y: { beginAtZero: true, max: 100 }
                }
            }
        });
    </script>
</body>
</html>
EOF

    echo "Dashboard generated: $output_file"
    echo "Open with: open $output_file"
}
```

## 完了条件

### 統合ヘルスチェック
- [ ] 全システムコンポーネントの監視が統合されている
- [ ] ヘルススコアが適切に計算される
- [ ] 詳細な診断情報が提供される
- [ ] ログファイルが適切に保存される

### 自動修復機能
- [ ] 一般的な問題の自動修復が動作する
- [ ] 修復成功率が表示される
- [ ] 修復不可能な問題が明確に報告される
- [ ] 修復後の検証が実行される

### 予防的メンテナンス
- [ ] 定期的なシステムクリーンアップが実行される
- [ ] セキュリティ監査が自動実行される
- [ ] パフォーマンス最適化が定期実行される
- [ ] 更新チェックが定期実行される

### パフォーマンス監視
- [ ] リアルタイムのシステムリソース監視
- [ ] パフォーマンス傾向の分析
- [ ] ボトルネック検出機能
- [ ] 最適化提案の自動生成

### レポート・ダッシュボード
- [ ] HTMLダッシュボードの生成
- [ ] 履歴データの可視化
- [ ] パフォーマンスチャートの表示
- [ ] アクセシブルなUI/UX

## 関連ファイル

- `scripts/system-health-master.sh` - マスターヘルスチェック
- `scripts/system-auto-fix.sh` - 自動修復システム
- `scripts/system-maintenance.sh` - 予防的メンテナンス
- `scripts/performance-monitor.sh` - パフォーマンス監視
- `scripts/generate-health-dashboard.sh` - ダッシュボード生成
- `nix/common/monitoring/` - 監視関連Nix設定

## 統合コマンド

実装完了後の利用可能コマンド：

```bash
# 基本ヘルスチェック
system-health              # マスターヘルスチェック実行
system-health --verbose     # 詳細診断モード
system-health --json       # JSON形式出力

# 自動修復・メンテナンス
system-auto-fix            # 自動修復実行
system-maintenance         # 予防的メンテナンス
system-optimize            # パフォーマンス最適化

# 監視・レポート
performance-monitor        # リアルタイム監視
health-dashboard           # HTMLダッシュボード生成
health-history             # 履歴データ表示

# エイリアス
health                     # system-health のエイリアス
fix                        # system-auto-fix のエイリアス
maintenance                # system-maintenance のエイリアス
```

---

**作成日**: 2025年7月13日  
**最終更新**: 2025年7月13日  
**作成者**: Claude Code Assistant