#!/bin/bash
# ドキュメント品質検証スクリプト
# リンク切れ、構造整合性、実行可能性をチェック

set -euo pipefail

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# 設定
DOCS_DIR="docs"
ERRORS=0
WARNINGS=0

echo "🔍 ドキュメント品質検証開始"
echo "📂 対象ディレクトリ: $DOCS_DIR"
echo ""

# ファイル存在チェック
check_file_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        return 0
    else
        return 1
    fi
}

# リンク切れチェック
check_internal_links() {
    log_info "内部リンク整合性チェック..."
    
    local link_errors=0
    
    find "$DOCS_DIR" -name "*.md" -type f | while read -r file; do
        # Markdownリンク [text](path) を抽出
        grep -oE '\]\([^)]+\.md[^)]*\)' "$file" 2>/dev/null | while read -r link; do
            # リンクパスを抽出 (]( と ) の間)
            local link_path=$(echo "$link" | sed 's/\](\([^)]*\))/\1/')
            
            # 相対パスを絶対パスに変換
            local base_dir=$(dirname "$file")
            local full_path
            
            if [[ "$link_path" =~ ^/ ]]; then
                # 絶対パス
                full_path="$link_path"
            else
                # 相対パス
                full_path="$base_dir/$link_path"
            fi
            
            # アンカーリンクを除去 (#section を除去)
            local file_path=$(echo "$full_path" | cut -d'#' -f1)
            
            if ! check_file_exists "$file_path"; then
                log_error "リンク切れ: $file → $link_path"
                ((link_errors++))
            fi
        done
    done
    
    if [[ $link_errors -eq 0 ]]; then
        log_success "内部リンク: 正常"
    else
        log_error "内部リンクエラー: ${link_errors}件"
        ((ERRORS += link_errors))
    fi
}

# 必須ファイル存在チェック
check_required_files() {
    log_info "必須ファイル存在チェック..."
    
    local required_files=(
        "$DOCS_DIR/README.md"
        "$DOCS_DIR/PHASE3_MASTER_STATUS.md"
        "$DOCS_DIR/CLEANUP_ANALYSIS_REPORT.md"
        "$DOCS_DIR/MAINTENANCE_IMPROVEMENT_PLAN.md"
        "$DOCS_DIR/SECURITY_ANALYSIS_REPORT.md"
    )
    
    for file in "${required_files[@]}"; do
        if check_file_exists "$file"; then
            log_success "必須ファイル存在: $(basename "$file")"
        else
            log_error "必須ファイル不在: $file"
            ((ERRORS++))
        fi
    done
}

# ディレクトリ構造チェック
check_directory_structure() {
    log_info "ディレクトリ構造チェック..."
    
    local required_dirs=(
        "$DOCS_DIR/guides"
        "$DOCS_DIR/reference"
        "$DOCS_DIR/archive"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_success "ディレクトリ存在: $(basename "$dir")/"
        else
            log_warning "ディレクトリ不在: $dir (統合実行前)"
            ((WARNINGS++))
        fi
    done
}

# 実行可能スクリプトチェック
check_executable_scripts() {
    log_info "実行可能スクリプトチェック..."
    
    local scripts=(
        "scripts/cleanup-phase1.sh"
        "scripts/consolidate-docs.sh"  
        "scripts/update-doc-references.sh"
        "scripts/validate-docs.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                log_success "実行可能: $script"
            else
                log_warning "実行権限なし: $script"
                log_info "修正: chmod +x $script"
                ((WARNINGS++))
            fi
        else
            log_error "スクリプトファイル不在: $script"
            ((ERRORS++))
        fi
    done
}

# マークダウン構文チェック
check_markdown_syntax() {
    log_info "Markdown構文チェック..."
    
    local syntax_errors=0
    
    find "$DOCS_DIR" -name "*.md" -type f | while read -r file; do
        # 基本的な構文チェック
        
        # ヘッダーレベルチェック (# から ###### まで)
        if grep -E '^#{7,}' "$file" >/dev/null 2>&1; then
            log_warning "不正なヘッダーレベル: $file (7個以上の#)"
            ((syntax_errors++))
        fi
        
        # 空のリンクチェック []() や [text]()
        if grep -E '\[[^\]]*\]\(\s*\)' "$file" >/dev/null 2>&1; then
            log_warning "空のリンク: $file"
            ((syntax_errors++))
        fi
        
        # 不完全なコードブロックチェック
        local code_blocks=$(grep -c '^```' "$file" 2>/dev/null || echo 0)
        if [[ $((code_blocks % 2)) -ne 0 ]]; then
            log_warning "不完全なコードブロック: $file"
            ((syntax_errors++))
        fi
    done
    
    if [[ $syntax_errors -eq 0 ]]; then
        log_success "Markdown構文: 正常"
    else
        log_warning "Markdown構文警告: ${syntax_errors}件"
        ((WARNINGS += syntax_errors))
    fi
}

# 実行可能アクション検証
check_executable_actions() {
    log_info "実行可能アクション検証..."
    
    # クリーンアップスクリプト検証
    if [[ -f "scripts/cleanup-phase1.sh" ]]; then
        if ./scripts/cleanup-phase1.sh true >/dev/null 2>&1; then
            log_success "クリーンアップスクリプト: DRY RUN正常"
        else
            log_error "クリーンアップスクリプト: DRY RUN失敗"
            ((ERRORS++))
        fi
    fi
    
    # セキュリティスクリプト存在確認
    if [[ -f "nix/security/scripts/setup-security.sh" ]]; then
        log_success "セキュリティセットアップスクリプト: 存在"
    else
        log_warning "セキュリティセットアップスクリプト: 不在"
        ((WARNINGS++))
    fi
    
    # パッケージ管理スクリプト確認
    if [[ -f "scripts/unified-package-manager.sh" ]]; then
        log_success "統合パッケージマネージャー: 存在"
    else
        log_warning "統合パッケージマネージャー: 不在"
        ((WARNINGS++))
    fi
}

# Phase3統合状況確認
check_phase3_consolidation() {
    log_info "Phase3統合状況確認..."
    
    # 統合マスター文書存在確認
    if check_file_exists "$DOCS_DIR/PHASE3_MASTER_STATUS.md"; then
        log_success "Phase3統合マスター文書: 存在"
    else
        log_error "Phase3統合マスター文書: 不在"
        ((ERRORS++))
    fi
    
    # 個別Phase3文書の統合確認
    local phase3_files=(
        "PHASE3_COMPLETE_IMPLEMENTATION_SCHEDULE.md"
        "PHASE3_COMPLETION_STATUS.md"
        "PHASE3_ENHANCEMENT_PROPOSALS.md"
        "PHASE3_IMPLEMENTATION_ROADMAP.md"
        "PHASE3_REMAINING_TASKS.md"
        "PHASE3_USAGE_GUIDE.md"
        "Next_Step.md"
    )
    
    local remaining_files=0
    for file in "${phase3_files[@]}"; do
        if check_file_exists "$DOCS_DIR/$file"; then
            log_warning "Phase3個別文書残存: $file (統合未実行)"
            ((remaining_files++))
        fi
    done
    
    if [[ $remaining_files -eq 0 ]]; then
        log_success "Phase3文書統合: 完了"
    else
        log_warning "Phase3文書統合: 未完了 (${remaining_files}件残存)"
        ((WARNINGS += remaining_files))
    fi
}

# メイン検証実行
echo "🔍 Phase 1: 基本構造検証"
check_required_files
check_directory_structure

echo ""
echo "🔍 Phase 2: リンク整合性検証"
check_internal_links

echo ""
echo "🔍 Phase 3: スクリプト実行可能性検証"
check_executable_scripts
check_executable_actions

echo ""
echo "🔍 Phase 4: コンテンツ品質検証"
check_markdown_syntax

echo ""
echo "🔍 Phase 5: 統合状況検証"
check_phase3_consolidation

echo ""
echo "📊 検証結果サマリー"

# 結果表示
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    log_success "🎉 ドキュメント品質: 完璧!"
    echo "✨ 全ての検証項目が正常です。"
elif [[ $ERRORS -eq 0 ]]; then
    log_warning "⚠️ ドキュメント品質: 良好 (警告あり)"
    echo "📋 警告: ${WARNINGS}件 (改善推奨)"
else
    log_error "❌ ドキュメント品質: 要修正"
    echo "🔧 エラー: ${ERRORS}件, 警告: ${WARNINGS}件"
fi

echo ""

# 改善推奨アクション
if [[ $WARNINGS -gt 0 || $ERRORS -gt 0 ]]; then
    echo "🛠️ 推奨改善アクション:"
    
    if [[ $remaining_files -gt 0 ]]; then
        echo "  1. ドキュメント統合実行:"
        echo "     ./scripts/consolidate-docs.sh false"
    fi
    
    if grep -q "実行権限なし" <<< "$(./scripts/validate-docs.sh 2>&1)" 2>/dev/null; then
        echo "  2. スクリプト実行権限付与:"
        echo "     chmod +x scripts/*.sh"
    fi
    
    if [[ $ERRORS -gt 0 ]]; then
        echo "  3. 重要エラー修正後再検証:"
        echo "     ./scripts/validate-docs.sh"
    fi
fi

echo ""
echo "✨ ドキュメント品質検証完了: $(date)"

# 終了コード
exit $ERRORS