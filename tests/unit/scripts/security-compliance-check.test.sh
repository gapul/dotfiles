#!/bin/bash
# Security Compliance Check Unit Tests

# テストフレームワーク読み込み
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/test-framework.sh"

# テスト対象スクリプト
SCRIPT_PATH="$(dirname "${BASH_SOURCE[0]}")/../../../scripts/security-compliance-check.sh"

# テスト: SOPS暗号化確認
test_sops_encryption_check() {
    # Age キーファイルをモック
    mkdir -p "$TEST_TEMP_DIR/.config/sops/age"
    echo "AGE-SECRET-KEY-1..." > "$TEST_TEMP_DIR/.config/sops/age/keys.txt"
    chmod 600 "$TEST_TEMP_DIR/.config/sops/age/keys.txt"
    
    # HOME環境変数を変更
    export HOME="$TEST_TEMP_DIR"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # check_sops_encryption関数をテスト
    local output
    output=$(check_sops_encryption 2>&1)
    
    assert_contains "$output" "Age キーファイル存在" "Output should contain Age key file check"
    assert_contains "$output" "権限: 適切" "Output should contain permission check"
}

# テスト: SSH設定確認
test_ssh_configuration_check() {
    # SSH設定をモック
    mkdir -p "$TEST_TEMP_DIR/.ssh"
    cat > "$TEST_TEMP_DIR/.ssh/config" << 'EOF'
Host *
    PasswordAuthentication no
    PubkeyAuthentication yes
EOF
    
    # SSH鍵をモック
    echo "mock private key" > "$TEST_TEMP_DIR/.ssh/id_ed25519"
    chmod 600 "$TEST_TEMP_DIR/.ssh/id_ed25519"
    
    # HOME環境変数を変更
    export HOME="$TEST_TEMP_DIR"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # check_ssh_configuration関数をテスト
    local output
    output=$(check_ssh_configuration 2>&1)
    
    assert_contains "$output" "SSH設定ファイル存在" "Output should contain SSH config check"
    assert_contains "$output" "パスワード認証無効化" "Output should contain password auth check"
}

# テスト: ファイル権限確認
test_file_permissions_check() {
    # 重要ファイルをモック
    mkdir -p "$TEST_TEMP_DIR/.ssh"
    echo "mock private key" > "$TEST_TEMP_DIR/.ssh/id_ed25519"
    chmod 600 "$TEST_TEMP_DIR/.ssh/id_ed25519"
    
    # HOME環境変数を変更
    export HOME="$TEST_TEMP_DIR"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # check_file_permissions関数をテスト
    local output
    output=$(check_file_permissions 2>&1)
    
    assert_contains "$output" "ファイル権限確認" "Output should contain file permission check"
    assert_contains "$output" "ファイル権限適切" "Output should contain proper permission check"
}

# テスト: ネットワークセキュリティ確認
test_network_security_check() {
    # netstatコマンドをモック
    create_mock_command "netstat" "$(cat << 'EOF'
tcp4       0      0  *.22                   *.*                    LISTEN
tcp6       0      0  *.22                   *.*                    LISTEN
tcp4       0      0  *.80                   *.*                    LISTEN
EOF
)"
    
    # macOS環境でのファイアウォールコマンドをモック
    create_mock_command "uname" "Darwin"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # check_network_security関数をテスト
    local output
    output=$(check_network_security 2>&1)
    
    assert_contains "$output" "ネットワークセキュリティ" "Output should contain network security check"
    assert_contains "$output" "開放ポート" "Output should contain open port check"
}

# テスト: シークレット漏洩確認
test_secret_exposure_check() {
    # テストファイルを作成
    mkdir -p "$TEST_TEMP_DIR/test-project"
    echo 'password = "secret123"' > "$TEST_TEMP_DIR/test-project/config.nix"
    echo 'api_key = "abc123"' > "$TEST_TEMP_DIR/test-project/settings.sh"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # DOTFILES_ROOTを変更
    DOTFILES_ROOT="$TEST_TEMP_DIR/test-project"
    
    # check_secret_exposure関数をテスト
    local output
    output=$(check_secret_exposure 2>&1)
    
    assert_contains "$output" "シークレット漏洩確認" "Output should contain secret exposure check"
    assert_contains "$output" "基本的なシークレットパターン" "Output should contain pattern check"
}

# テスト: Nixセキュリティ確認
test_nix_security_check() {
    # セキュリティベースライン設定をモック
    mkdir -p "$TEST_TEMP_DIR/nix/security/baseline"
    cat > "$TEST_TEMP_DIR/nix/security/baseline/security-baseline.nix" << 'EOF'
{ lib, ... }:
{
  nixpkgs.config.allowUnfree = false;
  # その他のセキュリティ設定
}
EOF
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # DOTFILES_ROOTを変更
    DOTFILES_ROOT="$TEST_TEMP_DIR"
    SECURITY_DIR="$TEST_TEMP_DIR/nix/security"
    
    # check_nix_security関数をテスト
    local output
    output=$(check_nix_security 2>&1)
    
    assert_contains "$output" "Nixセキュリティベースライン" "Output should contain Nix security check"
    assert_contains "$output" "セキュリティベースライン設定存在" "Output should contain baseline check"
}

# テスト: セキュリティスコア計算
test_security_score_calculation() {
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # エラーと警告の数を設定
    ERRORS=0
    WARNINGS=2
    
    # calculate_security_score関数をテスト
    local output
    output=$(calculate_security_score 2>&1)
    
    assert_contains "$output" "セキュリティスコア" "Output should contain security score"
    assert_contains "$output" "/100" "Output should contain score format"
}

# テスト: 改善提案
test_improvement_suggestions() {
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # エラーと警告の数を設定
    ERRORS=1
    WARNINGS=1
    
    # suggest_improvements関数をテスト
    local output
    output=$(suggest_improvements 2>&1)
    
    assert_contains "$output" "改善アクション提案" "Output should contain improvement suggestions"
    assert_contains "$output" "推奨改善アクション" "Output should contain recommended actions"
}

# テスト: エラーハンドリング
test_error_handling() {
    # 存在しないファイルでのテスト
    export HOME="$TEST_TEMP_DIR/nonexistent"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # エラーハンドリングをテスト
    local output
    output=$(check_sops_encryption 2>&1 || echo "expected failure")
    
    assert_contains "$output" "Age キーファイル不在" "Output should contain missing file error"
}

# テスト: 権限チェック
test_permission_validation() {
    # 不適切な権限のファイルを作成
    mkdir -p "$TEST_TEMP_DIR/.ssh"
    echo "mock private key" > "$TEST_TEMP_DIR/.ssh/id_ed25519"
    chmod 644 "$TEST_TEMP_DIR/.ssh/id_ed25519"  # 不適切な権限
    
    # HOME環境変数を変更
    export HOME="$TEST_TEMP_DIR"
    
    # スクリプトから関数を読み込み
    source "$SCRIPT_PATH"
    
    # check_file_permissions関数をテスト
    local output
    output=$(check_file_permissions 2>&1)
    
    assert_contains "$output" "権限要確認" "Output should contain permission warning"
}

# テストスイート実行
main() {
    run_test_suite "Security Compliance Check Tests" \
        test_sops_encryption_check \
        test_ssh_configuration_check \
        test_file_permissions_check \
        test_network_security_check \
        test_secret_exposure_check \
        test_nix_security_check \
        test_security_score_calculation \
        test_improvement_suggestions \
        test_error_handling \
        test_permission_validation
}

# 直接実行時
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi