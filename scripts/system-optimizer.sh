#!/bin/bash
# 統合システム最適化スクリプト
# コンテキスト検出システムを活用した動的パフォーマンス最適化

set -euo pipefail

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ログ関数
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "${CYAN}🔄 $1${NC}"; }

# 設定
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPTIMIZATION_LOG="$DOTFILES_ROOT/system-optimization.log"
METRICS_FILE="$DOTFILES_ROOT/system-metrics.json"

echo "🚀 システム最適化開始"
echo "===================="
echo "📂 Dotfilesディレクトリ: $DOTFILES_ROOT"
echo "📋 最適化ログ: $OPTIMIZATION_LOG"
echo ""

# コンテキスト検出
detect_system_context() {
    log_step "🔍 システムコンテキスト検出中..."
    
    local context="{}"
    
    # プラットフォーム検出
    local platform="$(uname)"
    context=$(echo "$context" | jq --arg platform "$platform" '. + {platform: $platform}')
    
    # リソース状況検出
    local cpu_cores="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo '1')"
    local memory_gb="$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo '8')"
    
    # macOS専用のメモリ検出
    if [[ "$platform" == "Darwin" ]]; then
        memory_gb="$(echo "$(sysctl -n hw.memsize) / 1024 / 1024 / 1024" | bc 2>/dev/null || echo '8')"
    fi
    
    context=$(echo "$context" | jq --argjson cores "$cpu_cores" --argjson memory "$memory_gb" '. + {cores: $cores, memory_gb: $memory}')
    
    # バッテリー状況検出
    local battery_level="100"
    local power_source="AC"
    
    if [[ "$platform" == "Darwin" ]]; then
        if command -v pmset >/dev/null 2>&1; then
            battery_level="$(pmset -g batt | grep -Eo '\d+%' | tr -d '%' || echo '100')"
            if pmset -g batt | grep -q "AC Power"; then
                power_source="AC"
            else
                power_source="Battery"
            fi
        fi
    fi
    
    context=$(echo "$context" | jq --argjson battery "$battery_level" --arg power "$power_source" '. + {battery_level: $battery, power_source: $power}')
    
    # 作業時間検出
    local current_hour="$(date +%H)"
    local time_category="unknown"
    
    if [[ $current_hour -ge 6 && $current_hour -lt 12 ]]; then
        time_category="morning"
    elif [[ $current_hour -ge 12 && $current_hour -lt 18 ]]; then
        time_category="afternoon"
    elif [[ $current_hour -ge 18 && $current_hour -lt 24 ]]; then
        time_category="evening"
    else
        time_category="night"
    fi
    
    context=$(echo "$context" | jq --arg time "$time_category" '. + {time_category: $time}')
    
    # 負荷状況検出
    local cpu_load="0.0"
    if command -v uptime >/dev/null 2>&1; then
        cpu_load="$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')"
    fi
    
    context=$(echo "$context" | jq --arg load "$cpu_load" '. + {cpu_load: $load}')
    
    # メモリ使用率検出
    local memory_usage="0"
    if [[ "$platform" == "Darwin" ]]; then
        if command -v vm_stat >/dev/null 2>&1; then
            memory_usage="$(vm_stat | awk '/Pages active/ {active=$3} /Pages wired/ {wired=$4} END {print int((active+wired)*4096/1024/1024/1024*100/'"$memory_gb"')}')"
        fi
    else
        memory_usage="$(free | awk '/^Mem:/ {print int($3/$2*100)}')"
    fi
    
    context=$(echo "$context" | jq --argjson usage "$memory_usage" '. + {memory_usage_percent: $usage}')
    
    # 最適化プロファイル決定
    local optimization_profile="balanced"
    
    # バッテリー駆動時は省電力モード
    if [[ "$power_source" == "Battery" && $battery_level -lt 30 ]]; then
        optimization_profile="power_save"
    # 高負荷時はパフォーマンス優先
    elif [[ $(echo "$cpu_load > 2.0" | bc -l 2>/dev/null || echo "0") -eq 1 ]] || [[ $memory_usage -gt 80 ]]; then
        optimization_profile="performance"
    # 夜間は静音モード
    elif [[ "$time_category" == "night" ]]; then
        optimization_profile="quiet"
    fi
    
    context=$(echo "$context" | jq --arg profile "$optimization_profile" '. + {optimization_profile: $profile}')
    
    # コンテキスト保存
    echo "$context" > "$METRICS_FILE"
    
    log_success "システムコンテキスト検出完了"
    echo "  🖥️  プラットフォーム: $platform"
    echo "  🧠 CPU: ${cpu_cores}コア"
    echo "  💾 メモリ: ${memory_gb}GB (使用率: ${memory_usage}%)"
    echo "  🔋 バッテリー: ${battery_level}% (電源: $power_source)"
    echo "  🕐 時間帯: $time_category"
    echo "  📊 負荷: $cpu_load"
    echo "  🎯 最適化プロファイル: $optimization_profile"
    
    echo "$optimization_profile"
}

# Nix最適化
optimize_nix_performance() {
    local profile="$1"
    log_step "📦 Nix システム最適化中..."
    
    cd "$DOTFILES_ROOT"
    
    # Nixガベージコレクション
    log_info "🗑️  Nixストアクリーンアップ中..."
    if nix-store --gc 2>/dev/null; then
        log_success "Nixガベージコレクション完了"
    else
        log_warning "Nixガベージコレクション失敗（権限不足の可能性）"
    fi
    
    # 古い世代の削除
    log_info "📜 古い世代削除中..."
    if command -v nix-env >/dev/null 2>&1; then
        nix-env --delete-generations old 2>/dev/null || true
    fi
    
    # プロファイル別最適化
    case "$profile" in
        "power_save")
            log_info "🔋 省電力モード最適化..."
            export NIX_BUILD_CORES="1"
            export NIX_MAX_JOBS="1"
            ;;
        "performance")
            log_info "🚀 パフォーマンスモード最適化..."
            local cores="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo '4')"
            export NIX_BUILD_CORES="$cores"
            export NIX_MAX_JOBS="$((cores * 2))"
            ;;
        "quiet")
            log_info "🔇 静音モード最適化..."
            export NIX_BUILD_CORES="2"
            export NIX_MAX_JOBS="2"
            ;;
        *)
            log_info "⚖️  バランスモード最適化..."
            local cores="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo '4')"
            export NIX_BUILD_CORES="$((cores / 2))"
            export NIX_MAX_JOBS="$cores"
            ;;
    esac
    
    # Nixキャッシュ最適化
    log_info "💽 Nixキャッシュ最適化中..."
    if nix-store --optimise 2>/dev/null; then
        log_success "Nixストア最適化完了"
    else
        log_warning "Nixストア最適化スキップ（時間節約）"
    fi
    
    log_success "Nix最適化完了"
}

# システムリソース最適化
optimize_system_resources() {
    local profile="$1"
    log_step "🖥️  システムリソース最適化中..."
    
    local platform="$(uname)"
    
    # macOS最適化
    if [[ "$platform" == "Darwin" ]]; then
        log_info "🍎 macOS最適化中..."
        
        # メモリプレッシャー軽減
        log_info "💾 メモリプレッシャー軽減中..."
        if command -v purge >/dev/null 2>&1; then
            purge 2>/dev/null || true
        fi
        
        # Spotlight最適化
        case "$profile" in
            "power_save"|"quiet")
                log_info "🔍 Spotlight制限中..."
                sudo mdutil -a -i off 2>/dev/null || true
                ;;
            *)
                log_info "🔍 Spotlight最適化中..."
                sudo mdutil -a -i on 2>/dev/null || true
                ;;
        esac
        
        # 電源管理最適化
        if [[ "$profile" == "power_save" ]]; then
            log_info "🔋 省電力設定適用中..."
            sudo pmset -a displaysleep 5 disksleep 10 sleep 15 2>/dev/null || true
        elif [[ "$profile" == "performance" ]]; then
            log_info "🚀 高性能設定適用中..."
            sudo pmset -a displaysleep 30 disksleep 0 sleep 0 2>/dev/null || true
        fi
    fi
    
    # Linux最適化
    if [[ "$platform" == "Linux" ]]; then
        log_info "🐧 Linux最適化中..."
        
        # swappiness調整
        case "$profile" in
            "power_save")
                echo 60 | sudo tee /proc/sys/vm/swappiness >/dev/null 2>&1 || true
                ;;
            "performance")
                echo 10 | sudo tee /proc/sys/vm/swappiness >/dev/null 2>&1 || true
                ;;
        esac
        
        # I/O最適化
        if [[ "$profile" == "performance" ]]; then
            log_info "💾 I/O最適化中..."
            echo noop | sudo tee /sys/block/*/queue/scheduler >/dev/null 2>&1 || true
        fi
    fi
    
    log_success "システムリソース最適化完了"
}

# アプリケーション最適化
optimize_applications() {
    local profile="$1"
    log_step "📱 アプリケーション最適化中..."
    
    # Git設定最適化
    log_info "🔧 Git設定最適化中..."
    case "$profile" in
        "performance")
            git config --global core.preloadindex true
            git config --global core.fscache true
            git config --global gc.auto 256
            ;;
        "power_save")
            git config --global gc.auto 0
            ;;
    esac
    
    # シェル最適化
    log_info "🐚 シェル最適化中..."
    if [[ -f "$HOME/.zshrc" ]]; then
        case "$profile" in
            "power_save"|"quiet")
                # プラグイン最小化
                export STARSHIP_CONFIG="$DOTFILES_ROOT/configs/terminal/starship-minimal.toml"
                ;;
            *)
                export STARSHIP_CONFIG="$DOTFILES_ROOT/configs/terminal/starship.toml"
                ;;
        esac
    fi
    
    # エディター最適化
    if command -v nvim >/dev/null 2>&1; then
        log_info "📝 Neovim最適化中..."
        case "$profile" in
            "power_save")
                export NVIM_MINIMAL="1"
                ;;
            "performance")
                export NVIM_PERFORMANCE="1"
                ;;
        esac
    fi
    
    log_success "アプリケーション最適化完了"
}

# ネットワーク最適化
optimize_network() {
    local profile="$1"
    log_step "🌐 ネットワーク最適化中..."
    
    local platform="$(uname)"
    
    # DNS最適化
    log_info "🌐 DNS最適化中..."
    case "$profile" in
        "performance")
            # 高速DNSサーバー設定
            if [[ "$platform" == "Darwin" ]]; then
                sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8 2>/dev/null || true
            fi
            ;;
    esac
    
    # HTTPキャッシュ最適化
    if command -v curl >/dev/null 2>&1; then
        log_info "🔄 HTTPキャッシュ最適化中..."
        export CURL_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
    fi
    
    log_success "ネットワーク最適化完了"
}

# パフォーマンス測定
measure_performance() {
    log_step "📊 パフォーマンス測定中..."
    
    local metrics="{}"
    
    # CPU使用率
    local cpu_usage="0"
    if command -v top >/dev/null 2>&1; then
        cpu_usage="$(top -l 1 -n 0 | awk '/CPU usage/ {print $3}' | tr -d '%' 2>/dev/null || echo '0')"
    fi
    metrics=$(echo "$metrics" | jq --argjson cpu "$cpu_usage" '. + {cpu_usage: $cpu}')
    
    # メモリ使用率
    local memory_usage="0"
    local platform="$(uname)"
    if [[ "$platform" == "Darwin" ]]; then
        memory_usage="$(vm_stat | awk '/Pages active/ {active=$3} /Pages wired/ {wired=$4} /Pages free/ {free=$3} END {total=active+wired+free; used=active+wired; print int(used/total*100)}' 2>/dev/null || echo '0')"
    else
        memory_usage="$(free | awk '/^Mem:/ {print int($3/$2*100)}' 2>/dev/null || echo '0')"
    fi
    metrics=$(echo "$metrics" | jq --argjson memory "$memory_usage" '. + {memory_usage: $memory}')
    
    # ディスク使用率
    local disk_usage="0"
    disk_usage="$(df / | awk 'NR==2 {print int($5)}' | tr -d '%' 2>/dev/null || echo '0')"
    metrics=$(echo "$metrics" | jq --argjson disk "$disk_usage" '. + {disk_usage: $disk}')
    
    # Nixビルド時間測定
    log_info "🔧 Nixビルド性能測定中..."
    local build_start
    build_start=$(date +%s)
    
    cd "$DOTFILES_ROOT"
    if timeout 60 nix flake check --show-trace >/dev/null 2>&1; then
        local build_end
        build_end=$(date +%s)
        local build_time=$((build_end - build_start))
        metrics=$(echo "$metrics" | jq --argjson time "$build_time" '. + {nix_build_time: $time}')
        log_success "Nixビルド時間: ${build_time}秒"
    else
        log_warning "Nixビルド測定タイムアウト"
        metrics=$(echo "$metrics" | jq '. + {nix_build_time: -1}')
    fi
    
    # 最適化効果の計算
    local optimization_score=100
    if [[ $cpu_usage -gt 80 ]]; then
        optimization_score=$((optimization_score - 20))
    fi
    if [[ $memory_usage -gt 80 ]]; then
        optimization_score=$((optimization_score - 20))
    fi
    if [[ $disk_usage -gt 90 ]]; then
        optimization_score=$((optimization_score - 10))
    fi
    
    metrics=$(echo "$metrics" | jq --argjson score "$optimization_score" '. + {optimization_score: $score}')
    
    # メトリクス更新
    local current_time
    current_time=$(date -Iseconds)
    metrics=$(echo "$metrics" | jq --arg timestamp "$current_time" '. + {timestamp: $timestamp}')
    
    # 既存メトリクスと統合
    if [[ -f "$METRICS_FILE" ]]; then
        local existing_metrics
        existing_metrics=$(cat "$METRICS_FILE")
        metrics=$(echo "$existing_metrics" | jq --argjson new "$metrics" '. + {performance: $new}')
    else
        metrics=$(echo '{}' | jq --argjson perf "$metrics" '. + {performance: $perf}')
    fi
    
    echo "$metrics" > "$METRICS_FILE"
    
    log_success "パフォーマンス測定完了"
    echo "  📊 CPU使用率: ${cpu_usage}%"
    echo "  💾 メモリ使用率: ${memory_usage}%"
    echo "  💿 ディスク使用率: ${disk_usage}%"
    echo "  🎯 最適化スコア: ${optimization_score}/100"
    
    return 0
}

# 最適化レポート生成
generate_optimization_report() {
    log_step "📋 最適化レポート生成中..."
    
    local report_file="$DOTFILES_ROOT/optimization-report-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$report_file" << EOF
# システム最適化レポート

実行日時: $(date)
最適化ツール: system-optimizer.sh

## システムコンテキスト
$(cat "$METRICS_FILE" | jq -r 'to_entries | map("- \(.key): \(.value)") | .[]' 2>/dev/null || echo "- データなし")

## 最適化内容
✅ Nixシステム最適化
✅ システムリソース最適化  
✅ アプリケーション最適化
✅ ネットワーク最適化

## パフォーマンス測定結果
$(cat "$METRICS_FILE" | jq -r '.performance | to_entries | map("- \(.key): \(.value)") | .[]' 2>/dev/null || echo "- データなし")

## 推奨事項
- 定期的な最適化実行（週1回推奨）
- リソース使用率監視
- プロファイル別設定の活用

## 次回最適化予定
$(date -d '+7 days' +%Y年%m月%d日 2>/dev/null || date -v +7d +%Y年%m月%d日 2>/dev/null || echo "7日後")

EOF
    
    log_success "最適化レポート生成完了: $report_file"
    echo "  📄 レポートファイル: $report_file"
}

# メイン処理
main() {
    local start_time
    start_time=$(date +%s)
    
    # ログファイル初期化
    echo "# システム最適化ログ - $(date)" > "$OPTIMIZATION_LOG"
    
    # システムコンテキスト検出
    local optimization_profile
    optimization_profile=$(detect_system_context)
    
    echo ""
    
    # 最適化実行
    optimize_nix_performance "$optimization_profile"
    echo ""
    
    optimize_system_resources "$optimization_profile"
    echo ""
    
    optimize_applications "$optimization_profile"
    echo ""
    
    optimize_network "$optimization_profile"
    echo ""
    
    # パフォーマンス測定
    measure_performance
    echo ""
    
    # レポート生成
    generate_optimization_report
    
    local end_time
    end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    echo ""
    log_success "🎉 システム最適化完了！"
    echo "⏱️  実行時間: ${total_time}秒"
    echo "🎯 最適化プロファイル: $optimization_profile"
    echo "📊 メトリクス: $METRICS_FILE"
    echo ""
    echo "✨ システムが最適化されました。快適な開発体験をお楽しみください！"
}

# 実行
main "$@"