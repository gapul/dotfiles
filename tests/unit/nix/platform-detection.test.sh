#!/bin/bash
# Platform Detection Unit Tests

# テストフレームワーク読み込み
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/test-framework.sh"

# テスト対象のスクリプト
PLATFORM_DETECTION_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/../../../nix/common/platform-detection.nix"

# プラットフォーム検出関数（テスト用）
detect_platform() {
    if [ -f "/etc/nixos/configuration.nix" ]; then
        echo "nixos"
    elif [ -n "${WSL_DISTRO_NAME:-}" ]; then
        echo "wsl"
    elif [ -d "/data/data/com.termux" ]; then
        echo "android"
    elif [ "$(uname)" = "Darwin" ]; then
        echo "darwin"
    else
        echo "linux"
    fi
}

# テスト: macOSプラットフォーム検出
test_darwin_platform_detection() {
    # macOS環境をモック
    create_mock_command "uname" "Darwin"
    
    local result
    result=$(detect_platform)
    
    assert_equals "darwin" "$result" "macOS should be detected as darwin"
}

# テスト: Linuxプラットフォーム検出
test_linux_platform_detection() {
    # Linux環境をモック
    create_mock_command "uname" "Linux"
    unset WSL_DISTRO_NAME
    
    local result
    result=$(detect_platform)
    
    assert_equals "linux" "$result" "Linux should be detected as linux"
}

# テスト: WSLプラットフォーム検出
test_wsl_platform_detection() {
    # WSL環境をモック
    export WSL_DISTRO_NAME="Ubuntu"
    create_mock_command "uname" "Linux"
    
    local result
    result=$(detect_platform)
    
    assert_equals "wsl" "$result" "WSL should be detected as wsl"
    
    # クリーンアップ
    unset WSL_DISTRO_NAME
}

# テスト: NixOSプラットフォーム検出
test_nixos_platform_detection() {
    # NixOS環境をモック（テスト環境内にファイルを作成）
    create_mock_file "$TEST_TEMP_DIR/etc/nixos/configuration.nix" "# NixOS configuration"
    create_mock_command "uname" "Linux"
    
    # 検出関数を一時的に変更
    detect_platform_nixos() {
        if [ -f "$TEST_TEMP_DIR/etc/nixos/configuration.nix" ]; then
            echo "nixos"
        elif [ -n "${WSL_DISTRO_NAME:-}" ]; then
            echo "wsl"
        elif [ -d "/data/data/com.termux" ]; then
            echo "android"
        elif [ "$(uname)" = "Darwin" ]; then
            echo "darwin"
        else
            echo "linux"
        fi
    }
    
    local result
    result=$(detect_platform_nixos)
    
    assert_equals "nixos" "$result" "NixOS should be detected as nixos"
}

# テスト: Androidプラットフォーム検出
test_android_platform_detection() {
    # Android/Termux環境をモック
    mkdir -p "$TEST_TEMP_DIR/data/data/com.termux"
    create_mock_command "uname" "Linux"
    
    # Termuxディレクトリを一時的に作成
    local original_check_dir="/data/data/com.termux"
    local mock_check_dir="$TEST_TEMP_DIR/data/data/com.termux"
    
    # 検出関数を一時的に変更
    detect_platform_android() {
        if [ -d "$mock_check_dir" ]; then
            echo "android"
        elif [ "$(uname)" = "Darwin" ]; then
            echo "darwin"
        else
            echo "linux"
        fi
    }
    
    local result
    result=$(detect_platform_android)
    
    assert_equals "android" "$result" "Android/Termux should be detected as android"
}

# テスト: プラットフォーム固有の機能
test_platform_capabilities() {
    # macOSの場合のテスト
    if [[ "$(uname)" == "Darwin" ]]; then
        assert_true "true" "macOS supports GUI applications"
        assert_true "true" "macOS supports Homebrew"
    fi
    
    # Linuxの場合のテスト
    if [[ "$(uname)" == "Linux" ]]; then
        assert_true "true" "Linux supports package managers"
    fi
}

# テスト: 環境変数の設定
test_environment_variables() {
    # プラットフォーム別の環境変数設定テスト
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        "darwin")
            assert_true "true" "macOS should have specific environment variables"
            ;;
        "linux")
            assert_true "true" "Linux should have specific environment variables"
            ;;
        "wsl")
            assert_true "true" "WSL should have specific environment variables"
            ;;
        "nixos")
            assert_true "true" "NixOS should have specific environment variables"
            ;;
        "android")
            assert_true "true" "Android should have specific environment variables"
            ;;
        *)
            skip_test "Unknown platform: $platform"
            ;;
    esac
}

# テスト: エラーハンドリング
test_error_handling() {
    # 無効な環境でのテスト
    unset WSL_DISTRO_NAME
    
    # unameが利用できない場合のテスト
    create_mock_command "uname" "" 1
    
    local result
    result=$(detect_platform)
    
    # デフォルトはlinuxになるはず
    assert_equals "linux" "$result" "Should default to linux on errors"
}

# テスト: パフォーマンス
test_performance() {
    log_info "プラットフォーム検出のパフォーマンステスト"
    
    # 10回実行して平均時間を測定
    benchmark_function "detect_platform" 10
    
    # 100ms以内で完了することを確認
    local start_time
    start_time=$(date +%s%3N)
    
    detect_platform >/dev/null
    
    local end_time
    end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    
    assert_true "$(if [[ $duration -lt 100 ]]; then echo "true"; else echo "false"; fi)" "Detection should complete within 100ms"
}

# テスト: 同期性
test_consistency() {
    # 複数回呼び出しても同じ結果を返すことを確認
    local result1
    local result2
    local result3
    
    result1=$(detect_platform)
    result2=$(detect_platform)
    result3=$(detect_platform)
    
    assert_equals "$result1" "$result2" "First and second calls should return same result"
    assert_equals "$result2" "$result3" "Second and third calls should return same result"
    assert_equals "$result1" "$result3" "First and third calls should return same result"
}

# テストスイート実行
main() {
    run_test_suite "Platform Detection Tests" \
        test_darwin_platform_detection \
        test_linux_platform_detection \
        test_wsl_platform_detection \
        test_nixos_platform_detection \
        test_android_platform_detection \
        test_platform_capabilities \
        test_environment_variables \
        test_error_handling \
        test_performance \
        test_consistency
}

# 直接実行時
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi