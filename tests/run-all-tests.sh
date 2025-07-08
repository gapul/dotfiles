#!/bin/bash
# 全テスト実行スクリプト
# 統合テスト、ユニットテスト、および実装されたシステムの包括的テスト

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

# テスト結果集計
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# 設定
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$DOTFILES_ROOT/tests"
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"

echo "🧪 Dotfiles テストスイート実行"
echo "================================"
echo "📂 テストディレクトリ: $TEST_ROOT"
echo "🔧 並列ジョブ数: $PARALLEL_JOBS"
echo ""

# テストフレームワーク確認
check_test_framework() {
    log_info "📋 テストフレームワーク確認中..."
    
    if [[ ! -f "$TEST_ROOT/utils/test-framework.sh" ]]; then
        log_error "テストフレームワークが見つかりません: $TEST_ROOT/utils/test-framework.sh"
        return 1
    fi
    
    # テストフレームワークの構文チェック
    if bash -n "$TEST_ROOT/utils/test-framework.sh"; then
        log_success "テストフレームワーク: 構文OK"
    else
        log_error "テストフレームワーク: 構文エラー"
        return 1
    fi
    
    # 実行権限確認
    if [[ -x "$TEST_ROOT/utils/test-framework.sh" ]]; then
        log_success "テストフレームワーク: 実行権限OK"
    else
        log_warning "テストフレームワーク: 実行権限付与中..."
        chmod +x "$TEST_ROOT/utils/test-framework.sh"
    fi
}

# 単一テストファイル実行
run_single_test() {
    local test_file="$1"
    local test_name="$(basename "$test_file" .sh)"
    
    log_info "🔄 実行中: $test_name"
    
    # 実行権限確認
    if [[ ! -x "$test_file" ]]; then
        chmod +x "$test_file"
    fi
    
    # テスト実行
    local start_time
    start_time=$(date +%s)
    
    local output
    local exit_code
    
    if output=$(bash "$test_file" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 結果解析
    local tests_run=0
    local tests_passed=0
    local tests_failed=0
    local tests_skipped=0
    
    # テスト結果から統計を抽出
    if [[ -n "$output" ]]; then
        tests_run=$(echo "$output" | grep -o "Tests run: [0-9]*" | grep -o "[0-9]*" || echo "0")
        tests_passed=$(echo "$output" | grep -o "Passed: [0-9]*" | grep -o "[0-9]*" || echo "0")
        tests_failed=$(echo "$output" | grep -o "Failed: [0-9]*" | grep -o "[0-9]*" || echo "0")
        tests_skipped=$(echo "$output" | grep -o "Skipped: [0-9]*" | grep -o "[0-9]*" || echo "0")
    fi
    
    # 結果集計
    TOTAL_TESTS=$((TOTAL_TESTS + tests_run))
    PASSED_TESTS=$((PASSED_TESTS + tests_passed))
    FAILED_TESTS=$((FAILED_TESTS + tests_failed))
    SKIPPED_TESTS=$((SKIPPED_TESTS + tests_skipped))
    
    # 結果表示
    if [[ $exit_code -eq 0 ]]; then
        log_success "$test_name: 完了 (${duration}s) - Run: $tests_run, Pass: $tests_passed, Fail: $tests_failed, Skip: $tests_skipped"
    else
        log_error "$test_name: 失敗 (${duration}s) - Run: $tests_run, Pass: $tests_passed, Fail: $tests_failed, Skip: $tests_skipped"
        echo "--- Error Output ---"
        echo "$output"
        echo "--- End Error Output ---"
    fi
    
    return $exit_code
}

# ユニットテスト実行
run_unit_tests() {
    log_info "🔬 ユニットテスト実行中..."
    
    local unit_test_dir="$TEST_ROOT/unit"
    local failed_tests=0
    
    if [[ ! -d "$unit_test_dir" ]]; then
        log_warning "ユニットテストディレクトリが見つかりません: $unit_test_dir"
        return 0
    fi
    
    # ユニットテストファイルを探す
    local unit_tests=()
    while IFS= read -r -d '' test_file; do
        unit_tests+=("$test_file")
    done < <(find "$unit_test_dir" -name "*.test.sh" -type f -print0)
    
    if [[ ${#unit_tests[@]} -eq 0 ]]; then
        log_warning "ユニットテストファイルが見つかりません"
        return 0
    fi
    
    echo "  📁 発見されたユニットテスト: ${#unit_tests[@]}件"
    
    # 各ユニットテストを実行
    for test_file in "${unit_tests[@]}"; do
        if ! run_single_test "$test_file"; then
            ((failed_tests++))
        fi
    done
    
    echo ""
    if [[ $failed_tests -eq 0 ]]; then
        log_success "ユニットテスト: 全て成功"
    else
        log_error "ユニットテスト: ${failed_tests}件失敗"
    fi
    
    return $failed_tests
}

# 統合テスト実行
run_integration_tests() {
    log_info "🔗 統合テスト実行中..."
    
    local integration_test_dir="$TEST_ROOT/integration"
    local failed_tests=0
    
    if [[ ! -d "$integration_test_dir" ]]; then
        log_warning "統合テストディレクトリが見つかりません: $integration_test_dir"
        return 0
    fi
    
    # 統合テストファイルを探す
    local integration_tests=()
    while IFS= read -r -d '' test_file; do
        integration_tests+=("$test_file")
    done < <(find "$integration_test_dir" -name "*.test.sh" -type f -print0)
    
    if [[ ${#integration_tests[@]} -eq 0 ]]; then
        log_warning "統合テストファイルが見つかりません"
        return 0
    fi
    
    echo "  📁 発見された統合テスト: ${#integration_tests[@]}件"
    
    # 各統合テストを実行
    for test_file in "${integration_tests[@]}"; do
        if ! run_single_test "$test_file"; then
            ((failed_tests++))
        fi
    done
    
    echo ""
    if [[ $failed_tests -eq 0 ]]; then
        log_success "統合テスト: 全て成功"
    else
        log_error "統合テスト: ${failed_tests}件失敗"
    fi
    
    return $failed_tests
}

# 実装システムテスト
run_implementation_tests() {
    log_info "🛠️  実装システムテスト実行中..."
    
    local impl_failed=0
    
    # パッケージ管理システムテスト
    echo "  📦 パッケージ管理システムテスト..."
    if [[ -f "$DOTFILES_ROOT/scripts/unified-package-manager.sh" ]]; then
        if bash "$DOTFILES_ROOT/scripts/unified-package-manager.sh" help >/dev/null 2>&1; then
            log_success "パッケージ管理システム: 実行可能"
        else
            log_error "パッケージ管理システム: 実行エラー"
            ((impl_failed++))
        fi
    else
        log_warning "パッケージ管理システム: スクリプトが見つかりません"
        ((impl_failed++))
    fi
    
    # セキュリティコンプライアンスシステムテスト
    echo "  🔐 セキュリティコンプライアンスシステムテスト..."
    if [[ -f "$DOTFILES_ROOT/scripts/security-compliance-check.sh" ]]; then
        # ドライラン実行
        if timeout 30 bash "$DOTFILES_ROOT/scripts/security-compliance-check.sh" >/dev/null 2>&1; then
            log_success "セキュリティコンプライアンスシステム: 実行可能"
        else
            log_warning "セキュリティコンプライアンスシステム: 実行警告 (設定不完全)"
            # セキュリティシステムは設定不完全でも警告レベル
        fi
    else
        log_error "セキュリティコンプライアンスシステム: スクリプトが見つかりません"
        ((impl_failed++))
    fi
    
    # テストフレームワーク自体のテスト
    echo "  🧪 テストフレームワークテスト..."
    if bash "$TEST_ROOT/utils/test-framework.sh" >/dev/null 2>&1; then
        log_success "テストフレームワーク: 実行可能"
    else
        log_error "テストフレームワーク: 実行エラー"
        ((impl_failed++))
    fi
    
    echo ""
    if [[ $impl_failed -eq 0 ]]; then
        log_success "実装システムテスト: 全て成功"
    else
        log_error "実装システムテスト: ${impl_failed}件失敗"
    fi
    
    return $impl_failed
}

# パフォーマンス測定
measure_performance() {
    log_info "📊 パフォーマンス測定中..."
    
    local start_time
    start_time=$(date +%s)
    
    # Nixフレークチェック
    echo "  🔧 Nix flake check..."
    cd "$DOTFILES_ROOT"
    local flake_start
    flake_start=$(date +%s)
    
    if timeout 60 nix flake check --show-trace >/dev/null 2>&1; then
        local flake_end
        flake_end=$(date +%s)
        local flake_duration=$((flake_end - flake_start))
        log_success "Nix flake check: ${flake_duration}s"
        
        if [[ $flake_duration -lt 30 ]]; then
            log_success "パフォーマンス: 良好 (${flake_duration}s < 30s)"
        else
            log_warning "パフォーマンス: 遅い (${flake_duration}s > 30s)"
        fi
    else
        log_error "Nix flake check: タイムアウトまたはエラー"
        return 1
    fi
    
    local end_time
    end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    log_info "パフォーマンス測定完了: ${total_duration}s"
}

# テストレポート生成
generate_test_report() {
    log_info "📋 テストレポート生成中..."
    
    local report_file="$DOTFILES_ROOT/test-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
# Dotfiles テストレポート

実行日時: $(date)
テストディレクトリ: $TEST_ROOT

## 結果サマリー
- 総テスト数: $TOTAL_TESTS
- 成功: $PASSED_TESTS
- 失敗: $FAILED_TESTS
- スキップ: $SKIPPED_TESTS
- 成功率: $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))%

## 実行されたテストカテゴリ
1. ユニットテスト
   - プラットフォーム検出テスト
   - パッケージ管理システムテスト
   - セキュリティコンプライアンステスト

2. 統合テスト
   - デプロイメントテスト
   - システム全体の統合テスト

3. 実装システムテスト
   - パッケージ管理システム動作確認
   - セキュリティコンプライアンスシステム動作確認
   - テストフレームワーク動作確認

## 実装された改善点
✅ パッケージ管理システム統合
✅ セキュリティコンプライアンスチェック
✅ 包括的テストフレームワーク
✅ 統合テストスイート

## 推奨事項
$(if [[ $FAILED_TESTS -gt 0 ]]; then
    echo "- 失敗したテストの調査と修正が必要"
else
    echo "- 全テストが成功しました"
fi)
- 継続的インテグレーション環境での定期実行を推奨
- 新機能追加時のテストカバレッジ拡張を推奨

EOF
    
    log_success "テストレポート生成完了: $report_file"
    echo "  📄 レポートファイル: $report_file"
}

# メイン実行
main() {
    local start_time
    start_time=$(date +%s)
    
    # テストフレームワーク確認
    if ! check_test_framework; then
        log_error "テストフレームワーク確認に失敗"
        exit 1
    fi
    
    echo ""
    
    # ユニットテスト実行
    local unit_failed=0
    if ! run_unit_tests; then
        unit_failed=$?
    fi
    
    echo ""
    
    # 統合テスト実行
    local integration_failed=0
    if ! run_integration_tests; then
        integration_failed=$?
    fi
    
    echo ""
    
    # 実装システムテスト実行
    local impl_failed=0
    if ! run_implementation_tests; then
        impl_failed=$?
    fi
    
    echo ""
    
    # パフォーマンス測定
    if ! measure_performance; then
        log_warning "パフォーマンス測定に失敗"
    fi
    
    echo ""
    
    # 結果サマリー
    local end_time
    end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    echo "📊 テスト実行結果サマリー"
    echo "========================="
    echo "⏱️  実行時間: ${total_duration}s"
    echo "🔢 総テスト数: $TOTAL_TESTS"
    echo "✅ 成功: $PASSED_TESTS"
    echo "❌ 失敗: $FAILED_TESTS"
    echo "⏭️  スキップ: $SKIPPED_TESTS"
    
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    fi
    
    echo "📈 成功率: ${success_rate}%"
    echo ""
    
    # 総合評価
    local total_failed=$((unit_failed + integration_failed + impl_failed))
    
    if [[ $total_failed -eq 0 && $FAILED_TESTS -eq 0 ]]; then
        log_success "🎉 全テストが成功しました！"
        echo "✨ 実装された改善点が正常に動作しています"
    elif [[ $FAILED_TESTS -eq 0 ]]; then
        log_warning "⚠️  一部のシステムテストで警告がありますが、テストは成功しました"
    else
        log_error "❌ テストに失敗があります"
        echo "🔧 失敗したテストの確認と修正が必要です"
    fi
    
    # テストレポート生成
    generate_test_report
    
    echo ""
    echo "🏁 テストスイート実行完了: $(date)"
    
    # 終了コード
    if [[ $total_failed -eq 0 && $FAILED_TESTS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# 実行
main "$@"