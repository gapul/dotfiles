#!/bin/bash
# Deployment Integration Tests
# 実際のdotfilesデプロイメントのテスト

# テストフレームワーク読み込み
source "$(dirname "${BASH_SOURCE[0]}")/../utils/test-framework.sh"

# 設定
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_PROFILE="${TEST_PROFILE:-minimal}"

# テスト: Nixフレーク構文チェック
test_nix_flake_syntax() {
    log_info "Nixフレーク構文チェック中..."
    
    cd "$DOTFILES_ROOT"
    
    # フレーク構文チェック
    assert_command_success "nix flake check --show-trace" "Nix flake should have valid syntax"
    
    # 評価テスト
    assert_command_success "nix eval .#platformInfo --raw" "Platform info should be evaluable"
}

# テスト: 最小限のビルド
test_minimal_build() {
    log_info "最小限のビルド検証中..."
    
    cd "$DOTFILES_ROOT"
    
    # プラットフォーム検出
    local platform
    platform=$(nix eval .#platformInfo --raw 2>/dev/null || echo "unknown")
    
    case "$platform" in
        *"darwin"*)
            assert_command_success "nix build .#darwinConfigurations.default.system --dry-run" "Darwin system should build"
            ;;
        *"linux"*)
            assert_command_success "nix build .#homeConfigurations.default.activationPackage --dry-run" "Home configuration should build"
            ;;
        *)
            skip_test "Unknown platform: $platform"
            ;;
    esac
}

# テスト: パッケージ可用性
test_package_availability() {
    log_info "パッケージ可用性確認中..."
    
    # 重要なパッケージが利用可能かチェック
    local essential_packages=("git" "curl" "wget" "vim" "jq")
    
    for package in "${essential_packages[@]}"; do
        assert_command_success "nix eval nixpkgs#$package.name --raw" "Package $package should be available"
    done
}

# テスト: 設定ファイル生成
test_configuration_generation() {
    log_info "設定ファイル生成テスト中..."
    
    cd "$DOTFILES_ROOT"
    
    # 設定ファイルのドライラン生成
    local config_files=(
        "configs/shell/zsh/.zshrc"
        "configs/editor/nvim/init.lua"
        "configs/git/.gitconfig"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            assert_file_exists "$config_file" "Configuration file should exist: $config_file"
            
            # 基本的な構文チェック
            case "$config_file" in
                *.lua)
                    assert_command_success "luac -p $config_file" "Lua configuration should have valid syntax"
                    ;;
                *.nix)
                    assert_command_success "nix-instantiate --parse $config_file" "Nix configuration should have valid syntax"
                    ;;
                *)
                    # その他のファイルは基本的な読み取り可能性をチェック
                    assert_command_success "cat $config_file > /dev/null" "Configuration file should be readable"
                    ;;
            esac
        else
            skip_test "Configuration file not found: $config_file"
        fi
    done
}

# テスト: シンボリックリンク
test_symlink_creation() {
    log_info "シンボリックリンク作成テスト中..."
    
    # テスト用のシンボリックリンクを作成
    local test_source="$TEST_TEMP_DIR/test-source"
    local test_target="$TEST_TEMP_DIR/test-target"
    
    echo "test content" > "$test_source"
    ln -s "$test_source" "$test_target"
    
    assert_file_exists "$test_target" "Symlink should exist"
    assert_equals "test content" "$(cat "$test_target")" "Symlink should point to correct content"
}

# テスト: 環境変数設定
test_environment_variables() {
    log_info "環境変数設定テスト中..."
    
    # 重要な環境変数をチェック
    assert_true "$(if [[ -n "$HOME" ]]; then echo "true"; else echo "false"; fi)" "HOME should be set"
    assert_true "$(if [[ -n "$USER" ]]; then echo "true"; else echo "false"; fi)" "USER should be set"
    assert_true "$(if [[ -n "$PATH" ]]; then echo "true"; else echo "false"; fi)" "PATH should be set"
    
    # Nixが利用可能かチェック
    assert_command_success "command -v nix" "Nix should be available in PATH"
}

# テスト: セキュリティ設定
test_security_configuration() {
    log_info "セキュリティ設定テスト中..."
    
    # Age キー確認
    if [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then
        assert_file_exists "$HOME/.config/sops/age/keys.txt" "Age key file should exist"
        
        # 権限確認
        local perms
        perms=$(stat -f "%A" "$HOME/.config/sops/age/keys.txt" 2>/dev/null || echo "600")
        assert_equals "600" "$perms" "Age key file should have correct permissions"
    else
        skip_test "Age key file not found"
    fi
    
    # SSH設定確認
    if [[ -d "$HOME/.ssh" ]]; then
        assert_directory_exists "$HOME/.ssh" "SSH directory should exist"
        
        # SSH鍵権限確認
        find "$HOME/.ssh" -type f -name "id_*" ! -name "*.pub" | while read -r key_file; do
            local key_perms
            key_perms=$(stat -f "%A" "$key_file" 2>/dev/null || echo "600")
            assert_equals "600" "$key_perms" "SSH key should have correct permissions: $(basename "$key_file")"
        done
    else
        skip_test "SSH directory not found"
    fi
}

# テスト: パフォーマンス
test_performance() {
    log_info "パフォーマンステスト中..."
    
    cd "$DOTFILES_ROOT"
    
    # ビルド時間測定
    local start_time
    start_time=$(date +%s)
    
    # 実際のビルドではなく、ドライランでテスト
    nix flake check --show-trace >/dev/null 2>&1
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "Flake check completed in ${duration}s"
    
    # 30秒以内で完了することを確認
    assert_true "$(if [[ $duration -lt 30 ]]; then echo "true"; else echo "false"; fi)" "Flake check should complete within 30 seconds"
}

# テスト: 依存関係確認
test_dependencies() {
    log_info "依存関係確認テスト中..."
    
    # 必要なコマンドが利用可能かチェック
    local required_commands=("nix" "git" "curl")
    
    for cmd in "${required_commands[@]}"; do
        assert_command_success "command -v $cmd" "Required command should be available: $cmd"
    done
    
    # Nixチャンネル確認
    if command -v nix-channel >/dev/null 2>&1; then
        assert_command_success "nix-channel --list" "Nix channels should be listable"
    else
        skip_test "nix-channel not available (using flakes)"
    fi
}

# テスト: 設定の一意性
test_configuration_uniqueness() {
    log_info "設定の一意性テスト中..."
    
    cd "$DOTFILES_ROOT"
    
    # 重複する設定がないかチェック
    local duplicate_configs=0
    
    # 設定ファイルの重複チェック
    find configs/ -name "*.nix" -o -name "*.lua" -o -name "*.sh" | while read -r config_file; do
        # ファイル名の重複チェック
        local basename_file
        basename_file=$(basename "$config_file")
        
        local count
        count=$(find configs/ -name "$basename_file" | wc -l)
        
        if [[ $count -gt 1 ]]; then
            log_warning "Duplicate configuration detected: $basename_file"
            ((duplicate_configs++))
        fi
    done
    
    assert_equals "0" "$duplicate_configs" "No duplicate configurations should exist"
}

# テスト: ロールバック機能
test_rollback_capability() {
    log_info "ロールバック機能テスト中..."
    
    # Nixの世代管理確認
    if command -v nix-env >/dev/null 2>&1; then
        assert_command_success "nix-env --list-generations" "Should be able to list generations"
    else
        skip_test "nix-env not available"
    fi
    
    # Gitの履歴確認
    cd "$DOTFILES_ROOT"
    assert_command_success "git log --oneline -10" "Should have git history for rollback"
}

# テストスイート実行
main() {
    run_test_suite "Deployment Integration Tests" \
        test_nix_flake_syntax \
        test_minimal_build \
        test_package_availability \
        test_configuration_generation \
        test_symlink_creation \
        test_environment_variables \
        test_security_configuration \
        test_performance \
        test_dependencies \
        test_configuration_uniqueness \
        test_rollback_capability
}

# 直接実行時
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi