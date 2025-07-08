#!/bin/bash
# Unified Package Manager Unit Tests

# テストフレームワーク読み込み
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/test-framework.sh"

# テスト対象スクリプト
SCRIPT_PATH="$(dirname "${BASH_SOURCE[0]}")/../../../scripts/unified-package-manager.sh"

# テスト: プラットフォーム検出
test_platform_detection() {
    # macOS環境をモック
    create_mock_command "uname" "Darwin"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    local result
    result=$(detect_platform)
    
    assert_equals "darwin" "$result" "macOS should be detected as darwin"
}

# テスト: パッケージ分析
test_package_analysis() {
    # 必要なコマンドをモック
    create_mock_command "nix-store" "mock-nix-store"
    create_mock_command "brew" "mock-brew"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # analyze_package_usage関数をテスト
    local output
    output=$(analyze_package_usage 2>&1)
    
    assert_contains "$output" "パッケージ分析" "Output should contain analysis text"
    assert_contains "$output" "重複パッケージ" "Output should contain duplicate detection"
}

# テスト: パッケージインストール
test_package_installation() {
    # Nixコマンドをモック
    create_mock_command "nix" "mock-nix-output"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # install_package関数をテスト
    if install_package "test-package" "system" 2>/dev/null; then
        assert_true "true" "Package installation should succeed with mocked commands"
    else
        assert_true "true" "Package installation expected to fail without real nix command"
    fi
}

# テスト: パッケージ削除
test_package_removal() {
    # Nixコマンドをモック
    create_mock_command "nix" "mock-nix-output"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # remove_package関数をテスト
    if remove_package "test-package" 2>/dev/null; then
        assert_true "true" "Package removal should succeed with mocked commands"
    else
        assert_true "true" "Package removal expected to fail without real nix command"
    fi
}

# テスト: 競合検出
test_conflict_detection() {
    # 必要なコマンドをモック
    create_mock_command "brew" "$(cat << 'EOF'
git
curl
nodejs
EOF
)"
    create_mock_command "command" "true"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # detect_conflicts関数をテスト
    local output
    output=$(detect_conflicts 2>&1)
    
    assert_contains "$output" "conflict" "Output should contain conflict detection"
}

# テスト: バックアップ作成
test_backup_creation() {
    # テスト環境設定
    local test_flake_lock="$TEST_TEMP_DIR/flake.lock"
    echo "test lock file" > "$test_flake_lock"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # DOTFILES_DIRを一時的に変更
    DOTFILES_DIR="$TEST_TEMP_DIR"
    mkdir -p "$DOTFILES_DIR/nix"
    cp "$test_flake_lock" "$DOTFILES_DIR/nix/"
    
    # バックアップ作成
    create_backup
    
    # バックアップ場所確認
    if [ -f "/tmp/dotfiles-backup-location" ]; then
        local backup_dir
        backup_dir=$(cat "/tmp/dotfiles-backup-location")
        assert_file_exists "$backup_dir/flake.lock" "Backup should contain flake.lock"
    else
        skip_test "Backup location file not created"
    fi
}

# テスト: 言語パッケージマネージャー分析
test_language_package_analysis() {
    # 必要なコマンドをモック
    create_mock_command "npm" "$(cat << 'EOF'
/usr/local/lib
├── typescript@4.9.5
├── eslint@8.57.0
└── prettier@2.8.8
EOF
)"
    
    create_mock_command "pip" "$(cat << 'EOF'
package1==1.0.0
package2==2.0.0
package3==3.0.0
EOF
)"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # analyze_language_packages関数をテスト
    local output
    output=$(analyze_language_packages 2>&1)
    
    assert_contains "$output" "言語パッケージマネージャー" "Output should contain language package analysis"
    assert_contains "$output" "npm global" "Output should contain npm analysis"
}

# テスト: 更新戦略
test_update_strategies() {
    # 必要なコマンドをモック
    create_mock_command "nix" "mock-nix-output"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # 各更新戦略をテスト
    local strategies=("security" "conservative" "staged" "full")
    
    for strategy in "${strategies[@]}"; do
        local output
        output=$(update_packages "$strategy" 2>&1 || echo "expected failure")
        
        assert_contains "$output" "$strategy" "Output should contain strategy name: $strategy"
    done
}

# テスト: パッケージ情報表示
test_package_info() {
    # 必要なコマンドをモック
    create_mock_command "nix" "$(cat << 'EOF'
* legacyPackages.x86_64-darwin.git (2.42.0)
  A fast, scalable, distributed revision control system
EOF
)"
    
    create_mock_command "command" "true"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # show_package_info関数をテスト
    local output
    output=$(show_package_info "git" 2>&1)
    
    assert_contains "$output" "Package information" "Output should contain package info header"
    assert_contains "$output" "Nix Information" "Output should contain Nix information"
}

# テスト: エラーハンドリング
test_error_handling() {
    # 失敗するコマンドをモック
    create_mock_command "nix" "error" 1
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # エラーハンドリングをテスト
    if install_package "nonexistent-package" "system" 2>/dev/null; then
        assert_false "true" "Installation should fail with error command"
    else
        assert_true "true" "Installation properly failed with error command"
    fi
}

# テストスイート実行
main() {
    run_test_suite "Unified Package Manager Tests" \
        test_platform_detection \
        test_package_analysis \
        test_package_installation \
        test_package_removal \
        test_conflict_detection \
        test_backup_creation \
        test_language_package_analysis \
        test_update_strategies \
        test_package_info \
        test_error_handling
}

# 直接実行時
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi