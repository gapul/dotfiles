#!/bin/bash
# Dotfiles テストフレームワーク
# シンプルなBashベースのテストフレームワーク

set -euo pipefail

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# テスト結果
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ログ関数
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_error() { echo -e "${RED}[FAIL]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_skip() { echo -e "${CYAN}[SKIP]${NC} $*"; }

# テスト環境変数
TEST_TEMP_DIR=""
TEST_ORIGINAL_PWD=""
TEST_ORIGINAL_HOME=""

# テストセットアップ
setup_test_environment() {
    log_info "テスト環境初期化中..."
    
    # 元の環境を保存
    TEST_ORIGINAL_PWD="$PWD"
    TEST_ORIGINAL_HOME="$HOME"
    
    # 一時ディレクトリ作成
    TEST_TEMP_DIR=$(mktemp -d -t dotfiles-test-XXXXXX)
    
    # テスト用のHOME設定
    export HOME="$TEST_TEMP_DIR/home"
    mkdir -p "$HOME"
    
    # 基本的なgit設定
    git config --global user.name "Test User" 2>/dev/null || true
    git config --global user.email "test@dotfiles.test" 2>/dev/null || true
    
    log_success "テスト環境初期化完了: $TEST_TEMP_DIR"
}

# テストクリーンアップ
cleanup_test_environment() {
    log_info "テスト環境クリーンアップ中..."
    
    # 元の環境を復元
    export HOME="$TEST_ORIGINAL_HOME"
    cd "$TEST_ORIGINAL_PWD"
    
    # 一時ディレクトリ削除
    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
        log_success "テスト環境クリーンアップ完了"
    fi
}

# アサーション関数

# 値の等価性チェック
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        log_success "assertEquals: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertEquals: $message"
        log_error "  Expected: '$expected'"
        log_error "  Actual:   '$actual'"
        return 1
    fi
}

# 値の不等価性チェック
assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$expected" != "$actual" ]]; then
        ((TESTS_PASSED++))
        log_success "assertNotEquals: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertNotEquals: $message"
        log_error "  Expected: NOT '$expected'"
        log_error "  Actual:   '$actual'"
        return 1
    fi
}

# 真偽値チェック
assert_true() {
    local value="$1"
    local message="${2:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$value" == "true" || "$value" == "0" ]]; then
        ((TESTS_PASSED++))
        log_success "assertTrue: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertTrue: $message"
        log_error "  Expected: true"
        log_error "  Actual:   '$value'"
        return 1
    fi
}

# 偽値チェック
assert_false() {
    local value="$1"
    local message="${2:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$value" == "false" || "$value" == "1" ]]; then
        ((TESTS_PASSED++))
        log_success "assertFalse: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertFalse: $message"
        log_error "  Expected: false"
        log_error "  Actual:   '$value'"
        return 1
    fi
}

# ファイル存在チェック
assert_file_exists() {
    local file="$1"
    local message="${2:-}"
    
    ((TESTS_RUN++))
    
    if [[ -f "$file" ]]; then
        ((TESTS_PASSED++))
        log_success "assertFileExists: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertFileExists: $message"
        log_error "  File not found: '$file'"
        return 1
    fi
}

# ファイル非存在チェック
assert_file_not_exists() {
    local file="$1"
    local message="${2:-}"
    
    ((TESTS_RUN++))
    
    if [[ ! -f "$file" ]]; then
        ((TESTS_PASSED++))
        log_success "assertFileNotExists: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertFileNotExists: $message"
        log_error "  File exists: '$file'"
        return 1
    fi
}

# ディレクトリ存在チェック
assert_directory_exists() {
    local dir="$1"
    local message="${2:-}"
    
    ((TESTS_RUN++))
    
    if [[ -d "$dir" ]]; then
        ((TESTS_PASSED++))
        log_success "assertDirectoryExists: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertDirectoryExists: $message"
        log_error "  Directory not found: '$dir'"
        return 1
    fi
}

# コマンド実行チェック
assert_command_success() {
    local command="$1"
    local message="${2:-}"
    
    ((TESTS_RUN++))
    
    if eval "$command" >/dev/null 2>&1; then
        ((TESTS_PASSED++))
        log_success "assertCommandSuccess: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertCommandSuccess: $message"
        log_error "  Command failed: '$command'"
        return 1
    fi
}

# コマンド失敗チェック
assert_command_failure() {
    local command="$1"
    local message="${2:-}"
    
    ((TESTS_RUN++))
    
    if ! eval "$command" >/dev/null 2>&1; then
        ((TESTS_PASSED++))
        log_success "assertCommandFailure: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertCommandFailure: $message"
        log_error "  Command succeeded: '$command'"
        return 1
    fi
}

# 文字列包含チェック
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$haystack" == *"$needle"* ]]; then
        ((TESTS_PASSED++))
        log_success "assertContains: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertContains: $message"
        log_error "  Haystack: '$haystack'"
        log_error "  Needle:   '$needle'"
        return 1
    fi
}

# 正規表現マッチチェック
assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$string" =~ $pattern ]]; then
        ((TESTS_PASSED++))
        log_success "assertMatches: $message"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "assertMatches: $message"
        log_error "  String:  '$string'"
        log_error "  Pattern: '$pattern'"
        return 1
    fi
}

# テストスキップ
skip_test() {
    local reason="$1"
    
    ((TESTS_RUN++))
    ((TESTS_SKIPPED++))
    log_skip "Test skipped: $reason"
}

# テスト実行関数
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_info "Running test: $test_name"
    
    # テストごとに環境をリセット
    setup_test_environment
    
    # テスト実行
    if $test_function; then
        log_success "Test completed: $test_name"
    else
        log_error "Test failed: $test_name"
    fi
    
    # クリーンアップ
    cleanup_test_environment
}

# テストスイート実行
run_test_suite() {
    local suite_name="$1"
    shift
    local tests=("$@")
    
    log_info "🧪 Running test suite: $suite_name"
    echo "================================="
    
    # 各テストを実行
    for test in "${tests[@]}"; do
        run_test "$test" "$test"
    done
    
    # 結果サマリー
    echo ""
    log_info "📊 Test Results for $suite_name:"
    log_info "  Tests run: $TESTS_RUN"
    log_success "  Passed: $TESTS_PASSED"
    log_error "  Failed: $TESTS_FAILED"
    log_skip "  Skipped: $TESTS_SKIPPED"
    
    # 成功率計算
    local success_rate=0
    if [[ $TESTS_RUN -gt 0 ]]; then
        success_rate=$(( (TESTS_PASSED * 100) / TESTS_RUN ))
    fi
    
    echo ""
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "🎉 All tests passed! Success rate: ${success_rate}%"
        return 0
    else
        log_error "❌ Some tests failed. Success rate: ${success_rate}%"
        return 1
    fi
}

# パフォーマンステスト
benchmark_function() {
    local function_name="$1"
    local iterations="${2:-10}"
    
    log_info "📊 Benchmarking: $function_name ($iterations iterations)"
    
    local total_time=0
    local i
    
    for ((i=1; i<=iterations; i++)); do
        local start_time
        start_time=$(date +%s%3N)
        
        # 関数実行
        eval "$function_name" >/dev/null 2>&1
        
        local end_time
        end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        
        total_time=$((total_time + duration))
        echo "  Iteration $i: ${duration}ms"
    done
    
    local average=$((total_time / iterations))
    log_info "  Average time: ${average}ms"
    log_info "  Total time: ${total_time}ms"
    
    return 0
}

# モックファイル作成
create_mock_file() {
    local file_path="$1"
    local content="${2:-# Mock file created by test framework}"
    
    mkdir -p "$(dirname "$file_path")"
    echo "$content" > "$file_path"
}

# モックコマンド作成
create_mock_command() {
    local command_name="$1"
    local mock_output="${2:-Mock output}"
    local exit_code="${3:-0}"
    
    local mock_script="$TEST_TEMP_DIR/bin/$command_name"
    mkdir -p "$(dirname "$mock_script")"
    
    cat > "$mock_script" << EOF
#!/bin/bash
echo "$mock_output"
exit $exit_code
EOF
    
    chmod +x "$mock_script"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"
}

# テストデータ生成
generate_test_data() {
    local data_type="$1"
    
    case "$data_type" in
        "nix-config")
            cat << 'EOF'
{ lib, pkgs, ... }:
{
  # Test Nix configuration
  environment.systemPackages = with pkgs; [
    git
    vim
  ];
}
EOF
            ;;
        "yaml-config")
            cat << 'EOF'
# Test YAML configuration
test:
  enabled: true
  value: "test-value"
  items:
    - item1
    - item2
EOF
            ;;
        "shell-script")
            cat << 'EOF'
#!/bin/bash
echo "Test shell script"
exit 0
EOF
            ;;
        *)
            echo "# Unknown test data type: $data_type"
            ;;
    esac
}

# テストレポート生成
generate_test_report() {
    local report_file="${1:-test-report.txt}"
    
    cat > "$report_file" << EOF
# Test Report

Generated: $(date)

## Summary
- Tests run: $TESTS_RUN
- Passed: $TESTS_PASSED
- Failed: $TESTS_FAILED
- Skipped: $TESTS_SKIPPED
- Success rate: $(( TESTS_RUN > 0 ? (TESTS_PASSED * 100) / TESTS_RUN : 0 ))%

## Test Environment
- Temp directory: $TEST_TEMP_DIR
- Original PWD: $TEST_ORIGINAL_PWD
- Original HOME: $TEST_ORIGINAL_HOME

## Status
$(if [[ $TESTS_FAILED -eq 0 ]]; then echo "✅ ALL TESTS PASSED"; else echo "❌ SOME TESTS FAILED"; fi)

EOF

    log_info "Test report generated: $report_file"
}

# ヘルプ表示
show_help() {
    cat << 'EOF'
Dotfiles Test Framework

USAGE:
  source test-framework.sh
  
FUNCTIONS:
  # Setup/Cleanup
  setup_test_environment        - Initialize test environment
  cleanup_test_environment      - Clean up test environment
  
  # Assertions
  assert_equals <expected> <actual> [message]
  assert_not_equals <expected> <actual> [message]
  assert_true <value> [message]
  assert_false <value> [message]
  assert_file_exists <file> [message]
  assert_file_not_exists <file> [message]
  assert_directory_exists <dir> [message]
  assert_command_success <command> [message]
  assert_command_failure <command> [message]
  assert_contains <haystack> <needle> [message]
  assert_matches <string> <pattern> [message]
  
  # Test Management
  run_test <name> <function>
  run_test_suite <suite_name> <test1> <test2> ...
  skip_test <reason>
  
  # Utilities
  benchmark_function <function> [iterations]
  create_mock_file <path> [content]
  create_mock_command <name> [output] [exit_code]
  generate_test_data <type>
  generate_test_report [file]

EXAMPLE:
  #!/bin/bash
  source tests/utils/test-framework.sh
  
  test_example() {
    assert_equals "hello" "hello" "String equality test"
    assert_file_exists "/etc/hosts" "System file exists"
    assert_command_success "ls /" "List root directory"
  }
  
  run_test_suite "Example Tests" test_example

EOF
}

# 直接実行時はヘルプを表示
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_help
fi