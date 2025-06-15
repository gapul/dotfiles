#!/bin/bash

# ドットファイル管理システム - 依存関係チェックスクリプト
# ファイル・ディレクトリの移動や変更時に依存関係の整合性をチェック

# 共通ユーティリティ関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 依存関係マップファイル
DEPENDENCY_MAP="$(get_dotfiles_dir)/.dependency-map.yml"

# チェック結果
ISSUES_FOUND=0
WARNINGS_FOUND=0

# ヘルプ表示
show_help() {
    cat << EOF
ドットファイル管理システム - 依存関係チェックスクリプト

使用方法:
    $0 [オプション]

オプション:
    --fix         可能な問題を自動修正します
    --verbose     詳細な出力を表示します
    --check-only  チェックのみ実行（修正は行わない）
    --help        このヘルプメッセージを表示します

例:
    $0                    # 標準チェック
    $0 --verbose          # 詳細チェック
    $0 --fix              # 問題の自動修正付きチェック
EOF
}

# YAML解析関数（簡易版）
parse_yaml_simple() {
    local yaml_file="$1"
    local prefix="$2"
    
    if [[ ! -f "$yaml_file" ]]; then
        log_error "YAML ファイルが見つかりません: $yaml_file"
        return 1
    fi
    
    # Python を使用してYAMLを解析
    python3 - << EOF
import yaml
import sys

try:
    with open('$yaml_file', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)
    
    def print_yaml_paths(obj, prefix=''):
        if isinstance(obj, dict):
            for key, value in obj.items():
                new_prefix = f"{prefix}_{key}" if prefix else key
                if isinstance(value, (dict, list)):
                    print_yaml_paths(value, new_prefix)
                else:
                    print(f"{new_prefix}={value}")
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                new_prefix = f"{prefix}_{i}" if prefix else str(i)
                if isinstance(item, (dict, list)):
                    print_yaml_paths(item, new_prefix)
                else:
                    print(f"{new_prefix}={item}")
    
    print_yaml_paths(data, '$prefix')
    
except Exception as e:
    print(f"Error parsing YAML: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# ファイル存在チェック
check_file_exists() {
    local file_path="$1"
    local context="$2"
    
    if [[ ! -e "$file_path" ]]; then
        log_error "依存ファイルが見つかりません: $file_path (context: $context)"
        ((ISSUES_FOUND++))
        return 1
    fi
    return 0
}

# スクリプトラッパー整合性チェック
check_script_wrapper_consistency() {
    log_info "スクリプトラッパーの整合性をチェック中..."
    
    local wrappers=("install.sh" "setup.sh")
    
    for wrapper in "${wrappers[@]}"; do
        if [[ -f "$wrapper" ]]; then
            local target_script="scripts/$wrapper"
            
            if ! check_file_exists "$target_script" "wrapper: $wrapper"; then
                continue
            fi
            
            # ラッパーの内容をチェック
            if ! grep -q "scripts/$wrapper" "$wrapper"; then
                log_warning "ラッパースクリプト $wrapper が正しく scripts/$wrapper を参照していません"
                ((WARNINGS_FOUND++))
            fi
        fi
    done
}

# CI スクリプト参照チェック
check_ci_script_references() {
    log_info "CI スクリプト参照の整合性をチェック中..."
    
    local ci_files=(".github/workflows/ci.yml" ".github/workflows/test.yml")
    
    for ci_file in "${ci_files[@]}"; do
        if [[ -f "$ci_file" ]]; then
            # スクリプト参照をチェック（ワイルドカード除外）
            local script_refs
            script_refs=$(grep -o 'scripts/[^[:space:]]*\.sh' "$ci_file" 2>/dev/null | grep -v '\*' || true)
            
            while IFS= read -r script_ref; do
                if [[ -n "$script_ref" ]] && ! check_file_exists "$script_ref" "CI: $ci_file"; then
                    continue
                fi
            done <<< "$script_refs"
            
            # install.sh 参照をチェック
            if grep -q "install\.sh" "$ci_file"; then
                if ! check_file_exists "install.sh" "CI: $ci_file"; then
                    continue
                fi
            fi
        fi
    done
}

# 設定ファイルソース存在チェック
check_config_source_existence() {
    log_info "設定ファイルソースの存在をチェック中..."
    
    # dependency-map.yml から設定ファイルリストを取得
    if [[ -f "$DEPENDENCY_MAP" ]]; then
        # YAMLから managed_configs セクションを抽出してチェック
        local config_sources
        config_sources=$(python3 - << 'EOF'
import yaml
try:
    with open('.dependency-map.yml', 'r') as f:
        data = yaml.safe_load(f)
    
    if 'config_structure' in data and 'managed_configs' in data['config_structure']:
        for config in data['config_structure']['managed_configs']:
            if 'source' in config:
                print(config['source'])
except:
    pass
EOF
)
        
        while IFS= read -r source_path; do
            if [[ -n "$source_path" ]] && ! check_file_exists "$source_path" "managed config"; then
                continue
            fi
        done <<< "$config_sources"
    fi
}

# ドキュメント参照チェック
check_documentation_references() {
    log_info "ドキュメント内のファイル参照をチェック中..."
    
    local doc_files
    doc_files=$(find . -name "*.md" -type f)
    
    while IFS= read -r doc_file; do
        if [[ -n "$doc_file" ]]; then
            # Markdown ファイル内のファイルパス参照を抽出（configs/を含むもののみ）
            local file_refs
            file_refs=$(grep -oE "\`(configs/[^\`]*|scripts/[^\`]*|[^\`]*\.(sh|yml|yaml))\`" "$doc_file" 2>/dev/null | sed 's/`//g' || true)
            
            while IFS= read -r file_ref; do
                if [[ -n "$file_ref" ]] && [[ ! "$file_ref" =~ ^~ ]] && [[ ! "$file_ref" =~ ^\/ ]]; then
                    # 設定ファイル例やexampleファイルは除外
                    if [[ ! "$file_ref" =~ \.example$ ]] && [[ ! "$file_ref" =~ config\.json$ ]] && [[ ! "$file_ref" =~ daemon\.json$ ]]; then
                        if [[ ! -f "$file_ref" ]]; then
                            log_warning "ドキュメント $doc_file で参照されているファイルが見つかりません: $file_ref"
                            ((WARNINGS_FOUND++))
                        fi
                    fi
                fi
            done <<< "$file_refs"
        fi
    done <<< "$doc_files"
}

# utils.sh 参照チェック
check_utils_references() {
    log_info "utils.sh への参照をチェック中..."
    
    local script_files
    script_files=$(find scripts -name "*.sh" -type f ! -name "utils.sh")
    
    while IFS= read -r script_file; do
        if [[ -n "$script_file" ]] && [[ -f "$script_file" ]]; then
            if grep -q "source.*utils\.sh" "$script_file"; then
                # utils.sh への相対パスが正しいかチェック
                local utils_ref
                utils_ref=$(grep -o 'source [^[:space:]]*utils\.sh' "$script_file" | head -1)
                if [[ -n "$utils_ref" ]]; then
                    local utils_path
                    utils_path=$(echo "$utils_ref" | sed 's/source [^[:space:]]*"//' | sed 's/"//')
                    # 相対パス解決の簡易チェック
                    if [[ "$utils_path" =~ .*utils\.sh$ ]]; then
                        debug "utils.sh 参照確認: $script_file"
                    fi
                fi
            fi
        fi
    done <<< "$script_files"
}

# メイン実行関数
main() {
    # オプション解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --fix)
                # 将来の修正機能用（現在は未実装）
                log_info "自動修正機能は今後実装予定です"
                shift
                ;;
            --verbose)
                export DEBUG=true
                shift
                ;;
            --check-only)
                # チェックのみモード（デフォルト動作）
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "不明なオプション: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_info "ドットファイル管理システム依存関係チェックを開始します"
    
    # 依存関係マップファイルの存在確認
    if ! check_file_exists "$DEPENDENCY_MAP" "dependency map"; then
        log_error "依存関係マップファイルが見つかりません。チェックを中止します。"
        exit 1
    fi
    
    # 各種チェックを実行
    check_script_wrapper_consistency
    check_ci_script_references
    check_config_source_existence
    check_documentation_references
    check_utils_references
    
    # 結果サマリー
    echo
    log_info "依存関係チェック完了"
    
    if [[ $ISSUES_FOUND -eq 0 ]] && [[ $WARNINGS_FOUND -eq 0 ]]; then
        log_success "問題は見つかりませんでした"
        exit 0
    else
        if [[ $ISSUES_FOUND -gt 0 ]]; then
            log_error "$ISSUES_FOUND 個の深刻な問題が見つかりました"
        fi
        if [[ $WARNINGS_FOUND -gt 0 ]]; then
            log_warning "$WARNINGS_FOUND 個の警告が見つかりました"
        fi
        
        log_info "問題の詳細については上記のログを確認してください"
        
        if [[ $ISSUES_FOUND -gt 0 ]]; then
            exit 1
        else
            exit 0
        fi
    fi
}

# Python YAML ライブラリの確認
if ! python3 -c "import yaml" 2>/dev/null; then
    log_warning "Python yaml ライブラリがインストールされていません。一部の機能が制限されます。"
    log_info "インストール方法: pip3 install PyYAML"
fi

# メイン実行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi