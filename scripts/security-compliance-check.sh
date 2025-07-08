#!/bin/bash
# セキュリティコンプライアンスチェック
# SOPS暗号化、SSH設定、ファイル権限などを自動検証

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
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECURITY_DIR="$DOTFILES_ROOT/nix/security"
ERRORS=0
WARNINGS=0

echo "🔍 セキュリティコンプライアンスチェック"
echo "======================================"
echo "📂 対象ディレクトリ: $DOTFILES_ROOT"
echo ""

# SOPS暗号化確認
check_sops_encryption() {
    log_info "📋 SOPS暗号化状態確認中..."
    
    # Age キー確認
    if [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then
        log_success "Age キーファイル存在: $HOME/.config/sops/age/keys.txt"
        
        # Age キーファイルの権限確認
        local age_perms
        age_perms=$(stat -f "%A" "$HOME/.config/sops/age/keys.txt" 2>/dev/null || echo "unknown")
        if [[ "$age_perms" == "600" ]]; then
            log_success "Age キーファイル権限: 適切 (600)"
        else
            log_warning "Age キーファイル権限: $age_perms (推奨: 600)"
            ((WARNINGS++))
        fi
    else
        log_error "Age キーファイル不在: $HOME/.config/sops/age/keys.txt"
        ((ERRORS++))
        return 1
    fi
    
    # SOPS設定ファイル確認
    if [[ -f "$SECURITY_DIR/sops/config/.sops.yaml" ]]; then
        log_success "SOPS設定ファイル存在"
    else
        log_error "SOPS設定ファイル不在: $SECURITY_DIR/sops/config/.sops.yaml"
        ((ERRORS++))
        return 1
    fi
    
    # 暗号化されたシークレットファイル確認
    local encrypted_files=0
    local unencrypted_files=0
    
    find "$SECURITY_DIR/sops" -name "secrets*.yaml" -not -name "*.example" | while read -r file; do
        if [[ -f "$file" ]]; then
            if grep -q "^sops:" "$file"; then
                log_success "暗号化済み: $(basename "$file")"
                ((encrypted_files++))
            else
                log_error "暗号化されていないシークレットファイル: $file"
                ((unencrypted_files++))
            fi
        fi
    done
    
    # 結果確認
    if [[ $encrypted_files -gt 0 ]]; then
        log_success "SOPS暗号化: $encrypted_files 個のファイルが適切に暗号化済み"
    else
        log_warning "SOPS暗号化: 暗号化されたファイルが見つかりません"
        ((WARNINGS++))
    fi
    
    if [[ $unencrypted_files -gt 0 ]]; then
        log_error "SOPS暗号化: $unencrypted_files 個のファイルが平文で保存されています"
        ((ERRORS++))
    fi
}

# SSH設定確認
check_ssh_configuration() {
    log_info "🔐 SSH設定確認中..."
    
    # SSH設定ファイル確認
    local ssh_config="$HOME/.ssh/config"
    if [[ -f "$ssh_config" ]]; then
        log_success "SSH設定ファイル存在"
        
        # パスワード認証無効化確認
        if grep -q "PasswordAuthentication no" "$ssh_config"; then
            log_success "SSH パスワード認証無効化"
        else
            log_warning "SSH パスワード認証が無効化されていません"
            ((WARNINGS++))
        fi
        
        # 鍵認証設定確認
        if grep -q "PubkeyAuthentication yes" "$ssh_config"; then
            log_success "SSH 鍵認証有効化"
        else
            log_info "SSH 鍵認証設定未確認 (デフォルト有効)"
        fi
    else
        log_warning "SSH設定ファイル不在: $ssh_config"
        ((WARNINGS++))
    fi
    
    # SSH鍵ファイル権限確認
    if [[ -d "$HOME/.ssh" ]]; then
        find "$HOME/.ssh" -type f -name "id_*" ! -name "*.pub" -exec ls -la {} \; | \
        while read -r line; do
            local perms
            perms=$(echo "$line" | awk '{print $1}')
            local file
            file=$(echo "$line" | awk '{print $NF}')
            
            if [[ "$perms" == "-rw-------" ]]; then
                log_success "SSH鍵権限適切: $(basename "$file")"
            else
                log_error "不安全なSSH鍵権限: $file ($perms)"
                ((ERRORS++))
            fi
        done
    fi
}

# ファイル権限確認
check_file_permissions() {
    log_info "📁 ファイル権限確認中..."
    
    # 重要ファイルの権限確認
    local important_files=(
        "$HOME/.ssh/id_rsa:600"
        "$HOME/.ssh/id_ed25519:600"
        "$HOME/.config/sops/age/keys.txt:600"
        "$HOME/.gnupg/secring.gpg:600"
        "$HOME/.gnupg/pubring.gpg:644"
    )
    
    for file_perm in "${important_files[@]}"; do
        local file="${file_perm%:*}"
        local expected_perm="${file_perm#*:}"
        
        if [[ -f "$file" ]]; then
            local actual_perm
            actual_perm=$(stat -f "%A" "$file" 2>/dev/null || echo "unknown")
            
            if [[ "$actual_perm" == "$expected_perm" ]]; then
                log_success "ファイル権限適切: $(basename "$file") ($actual_perm)"
            else
                log_warning "ファイル権限要確認: $file (現在: $actual_perm, 推奨: $expected_perm)"
                ((WARNINGS++))
            fi
        fi
    done
    
    # dotfilesディレクトリの権限確認
    local dotfiles_perm
    dotfiles_perm=$(stat -f "%A" "$DOTFILES_ROOT" 2>/dev/null || echo "unknown")
    if [[ "$dotfiles_perm" == "755" ]]; then
        log_success "dotfilesディレクトリ権限: 適切 (755)"
    else
        log_info "dotfilesディレクトリ権限: $dotfiles_perm"
    fi
}

# ネットワークセキュリティ確認
check_network_security() {
    log_info "🌐 ネットワークセキュリティ確認中..."
    
    # 開放ポート確認
    if command -v netstat >/dev/null 2>&1; then
        local open_ports
        open_ports=$(netstat -tuln | grep -E ':(22|80|443|8080|3000|5000|8000)' | wc -l)
        
        if [[ $open_ports -gt 5 ]]; then
            log_warning "多数のポートが開放されています ($open_ports 個)"
            ((WARNINGS++))
            
            log_info "開放ポート一覧:"
            netstat -tuln | grep -E ':(22|80|443|8080|3000|5000|8000)' | while read -r line; do
                echo "    $line"
            done
        else
            log_success "開放ポート数: 適切 ($open_ports 個)"
        fi
    else
        log_info "netstat不在 - ポート確認スキップ"
    fi
    
    # ファイアウォール確認 (macOS)
    if [[ "$(uname)" == "Darwin" ]]; then
        if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q "enabled"; then
            log_success "macOS ファイアウォール: 有効"
        else
            log_warning "macOS ファイアウォール: 無効"
            ((WARNINGS++))
        fi
    fi
}

# シークレット漏洩確認
check_secret_exposure() {
    log_info "🕵️  シークレット漏洩確認中..."
    
    # gitleaksで確認
    if command -v gitleaks >/dev/null 2>&1; then
        log_info "gitleaksでシークレット漏洩スキャン中..."
        
        cd "$DOTFILES_ROOT"
        if gitleaks detect --source . --verbose --no-git; then
            log_success "gitleaks: シークレット漏洩なし"
        else
            log_error "gitleaks: 潜在的なシークレット漏洩を検出"
            ((ERRORS++))
        fi
    else
        log_warning "gitleaks未インストール - シークレット漏洩スキャンスキップ"
        ((WARNINGS++))
    fi
    
    # 基本的なパターン確認
    log_info "基本的なシークレットパターン確認中..."
    
    local secret_patterns=(
        "password\s*=\s*['\"][^'\"]*['\"]"
        "api_key\s*=\s*['\"][^'\"]*['\"]"
        "secret\s*=\s*['\"][^'\"]*['\"]"
        "token\s*=\s*['\"][^'\"]*['\"]"
        "BEGIN.*PRIVATE.*KEY"
    )
    
    for pattern in "${secret_patterns[@]}"; do
        if find "$DOTFILES_ROOT" -type f -name "*.nix" -o -name "*.sh" -o -name "*.yaml" | \
           grep -v ".git" | grep -v "example" | \
           xargs grep -l "$pattern" 2>/dev/null; then
            log_warning "潜在的なシークレットパターン検出: $pattern"
            ((WARNINGS++))
        fi
    done
}

# Nixセキュリティベースライン確認
check_nix_security() {
    log_info "📦 Nixセキュリティベースライン確認中..."
    
    # セキュリティベースライン設定確認
    if [[ -f "$SECURITY_DIR/baseline/security-baseline.nix" ]]; then
        log_success "セキュリティベースライン設定存在"
        
        # 重要なセキュリティ設定確認
        if grep -q "allowUnfree.*false" "$SECURITY_DIR/baseline/security-baseline.nix"; then
            log_success "Nixセキュリティ: 非フリーパッケージ制限有効"
        else
            log_warning "Nixセキュリティ: 非フリーパッケージ制限未確認"
            ((WARNINGS++))
        fi
    else
        log_warning "セキュリティベースライン設定不在"
        ((WARNINGS++))
    fi
    
    # Nixストア権限確認
    if [[ -d "/nix/store" ]]; then
        local nix_store_perm
        nix_store_perm=$(stat -f "%A" "/nix/store" 2>/dev/null || echo "unknown")
        
        if [[ "$nix_store_perm" == "755" ]]; then
            log_success "Nixストア権限: 適切 (755)"
        else
            log_warning "Nixストア権限: $nix_store_perm (推奨: 755)"
            ((WARNINGS++))
        fi
    fi
}

# セキュリティスコア計算
calculate_security_score() {
    log_info "📊 セキュリティスコア計算中..."
    
    local total_checks=6  # 総チェック数
    local passed_checks=$((total_checks - ERRORS))
    local score=$(( (passed_checks * 100) / total_checks ))
    
    echo ""
    log_info "🎯 セキュリティスコア: $score/100"
    
    if [[ $score -ge 90 ]]; then
        log_success "セキュリティ状態: 優秀 (${score}%)"
    elif [[ $score -ge 70 ]]; then
        log_warning "セキュリティ状態: 良好 (${score}%)"
    else
        log_error "セキュリティ状態: 要改善 (${score}%)"
    fi
}

# 改善アクション提案
suggest_improvements() {
    log_info "🛠️  改善アクション提案..."
    
    if [[ $ERRORS -gt 0 || $WARNINGS -gt 0 ]]; then
        echo ""
        echo "📋 推奨改善アクション:"
        
        if [[ $ERRORS -gt 0 ]]; then
            echo "  🔴 重要 (エラー修正):"
            echo "    1. SOPS暗号化セットアップ実行:"
            echo "       ./nix/security/scripts/setup-security.sh"
            echo "    2. SSH鍵権限修正:"
            echo "       chmod 600 ~/.ssh/id_*"
            echo "    3. シークレット漏洩修正:"
            echo "       平文のシークレットをSOPS暗号化"
        fi
        
        if [[ $WARNINGS -gt 0 ]]; then
            echo "  🟡 推奨 (警告対応):"
            echo "    1. SSH設定強化:"
            echo "       echo 'PasswordAuthentication no' >> ~/.ssh/config"
            echo "    2. ファイアウォール有効化:"
            echo "       sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"
            echo "    3. gitleaksインストール:"
            echo "       nix profile install nixpkgs#gitleaks"
        fi
    else
        log_success "セキュリティ状態良好 - 改善アクション不要"
    fi
}

# メイン実行
main() {
    echo "🔄 Phase 1: SOPS暗号化確認"
    check_sops_encryption
    
    echo ""
    echo "🔄 Phase 2: SSH設定確認"
    check_ssh_configuration
    
    echo ""
    echo "🔄 Phase 3: ファイル権限確認"
    check_file_permissions
    
    echo ""
    echo "🔄 Phase 4: ネットワークセキュリティ確認"
    check_network_security
    
    echo ""
    echo "🔄 Phase 5: シークレット漏洩確認"
    check_secret_exposure
    
    echo ""
    echo "🔄 Phase 6: Nixセキュリティベースライン確認"
    check_nix_security
    
    echo ""
    echo "📊 セキュリティコンプライアンス結果"
    echo "=================================="
    
    # 結果サマリー
    if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
        log_success "🎉 セキュリティコンプライアンス: 完璧!"
        echo "✨ 全てのセキュリティチェックが合格しました"
    elif [[ $ERRORS -eq 0 ]]; then
        log_warning "⚠️ セキュリティコンプライアンス: 良好 (警告あり)"
        echo "📋 警告: ${WARNINGS}件 (改善推奨)"
    else
        log_error "❌ セキュリティコンプライアンス: 要修正"
        echo "🔧 エラー: ${ERRORS}件, 警告: ${WARNINGS}件"
    fi
    
    calculate_security_score
    suggest_improvements
    
    echo ""
    echo "✨ セキュリティコンプライアンスチェック完了: $(date)"
    
    # 終了コード
    exit $ERRORS
}

# 実行
main "$@"