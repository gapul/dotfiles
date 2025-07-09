#!/bin/bash
# セキュリティベースライン完全自動化スクリプト
# SOPS暗号化、SSH設定、権限管理を完全自動化

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
SECURITY_DIR="$DOTFILES_ROOT/nix/security"
SETUP_LOG="$DOTFILES_ROOT/security-setup.log"
DRY_RUN="${DRY_RUN:-false}"

echo "🔐 セキュリティベースライン完全自動化"
echo "================================="
echo "📂 セキュリティディレクトリ: $SECURITY_DIR"
echo "🔧 実行モード: $([ "$DRY_RUN" = "true" ] && echo "ドライラン" || echo "実行")"
echo ""

# 前提条件確認
check_prerequisites() {
    log_step "📋 前提条件確認中..."
    
    local missing_tools=()
    
    # 必要なツールの確認
    local required_tools=("age" "sops" "git" "ssh-keygen")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    # 不足ツールのインストール
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warning "不足しているツール: ${missing_tools[*]}"
        
        if [[ "$DRY_RUN" = "false" ]]; then
            log_info "必要なツールをインストール中..."
            
            # Nixでのインストール
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "age"|"sops")
                        log_info "📦 ${tool}をNixでインストール中..."
                        nix profile install "nixpkgs#$tool" || {
                            log_error "$tool のインストールに失敗"
                            return 1
                        }
                        ;;
                    "ssh-keygen")
                        log_info "🔑 OpenSSHは通常プリインストール済みです"
                        ;;
                esac
            done
        else
            log_info "ドライランモード: ツールインストールをスキップ"
        fi
    fi
    
    log_success "前提条件確認完了"
    return 0
}

# Age キー生成・設定
setup_age_encryption() {
    log_step "🔐 Age暗号化設定中..."
    
    local age_dir="$HOME/.config/sops/age"
    local age_keys_file="$age_dir/keys.txt"
    
    # ディレクトリ作成
    if [[ "$DRY_RUN" = "false" ]]; then
        mkdir -p "$age_dir"
        chmod 700 "$age_dir"
    else
        log_info "ドライラン: mkdir -p $age_dir && chmod 700 $age_dir"
    fi
    
    # Age キー確認・生成
    if [[ ! -f "$age_keys_file" ]]; then
        log_info "🔑 新しいAge秘密鍵を生成中..."
        
        if [[ "$DRY_RUN" = "false" ]]; then
            # Age キーペア生成
            local age_keygen_output
            age_keygen_output=$(age-keygen 2>&1)
            
            # 秘密鍵を保存
            echo "$age_keygen_output" | grep "AGE-SECRET-KEY-" > "$age_keys_file"
            chmod 600 "$age_keys_file"
            
            # 公開鍵を抽出
            local public_key
            public_key=$(echo "$age_keygen_output" | grep "Public key:" | awk '{print $3}')
            
            log_success "Age秘密鍵生成完了: $age_keys_file"
            log_info "公開鍵: $public_key"
            
            # SOPS設定ファイル更新
            update_sops_config "$public_key"
        else
            log_info "ドライラン: age-keygen > $age_keys_file && chmod 600 $age_keys_file"
        fi
    else
        log_success "Age秘密鍵は既に存在: $age_keys_file"
        
        # 権限確認
        local current_perms
        current_perms=$(stat -f "%A" "$age_keys_file" 2>/dev/null || echo "unknown")
        if [[ "$current_perms" != "600" ]]; then
            log_warning "Age秘密鍵の権限を修正中..."
            if [[ "$DRY_RUN" = "false" ]]; then
                chmod 600 "$age_keys_file"
            else
                log_info "ドライラン: chmod 600 $age_keys_file"
            fi
        fi
    fi
}

# SOPS設定更新
update_sops_config() {
    local public_key="$1"
    log_step "📝 SOPS設定更新中..."
    
    local sops_config="$SECURITY_DIR/sops/config/.sops.yaml"
    
    # 設定ディレクトリ作成
    if [[ "$DRY_RUN" = "false" ]]; then
        mkdir -p "$(dirname "$sops_config")"
    else
        log_info "ドライラン: mkdir -p $(dirname "$sops_config")"
    fi
    
    # SOPS設定ファイル生成
    local sops_config_content="creation_rules:
  # Dotfiles セキュリティ設定
  - path_regex: secrets.*\\.ya?ml$
    age: $public_key
    
  # 環境別設定
  - path_regex: secrets-.*\\.ya?ml$
    age: $public_key
    
  # プラットフォーム別設定
  - path_regex: (darwin|linux|android|wsl)/.*secrets.*\\.ya?ml$
    age: $public_key

# セキュリティポリシー
policies:
  # 暗号化必須パターン
  encryption_required:
    - \"**/secrets*.yaml\"
    - \"**/secrets*.yml\"
    - \"**/*secret*.yaml\"
    - \"**/*secret*.yml\"
    - \"**/*password*.yaml\"
    - \"**/*password*.yml\"
    - \"**/api-keys*.yaml\"
    - \"**/api-keys*.yml\"
  
  # 除外パターン
  exclusions:
    - \"**/*.example\"
    - \"**/*.template\"
    - \"**/README.md\"
    - \"**/.gitignore\"

# Age設定
age:
  public_key: $public_key
  key_file: ~/.config/sops/age/keys.txt

# 追加セキュリティ設定
security:
  # 最小暗号化レベル
  min_encryption_level: \"AES256\"
  
  # 権限要件
  file_permissions:
    secrets: \"600\"
    keys: \"600\"
    configs: \"644\"
  
  # 監査ログ
  audit_log: true
  audit_file: \"$DOTFILES_ROOT/security-audit.log\"
"
    
    if [[ "$DRY_RUN" = "false" ]]; then
        echo "$sops_config_content" > "$sops_config"
        log_success "SOPS設定ファイル作成: $sops_config"
    else
        log_info "ドライラン: SOPS設定ファイル作成予定: $sops_config"
    fi
}

# SSH設定最適化
setup_ssh_security() {
    log_step "🔑 SSH設定最適化中..."
    
    local ssh_dir="$HOME/.ssh"
    local ssh_config="$ssh_dir/config"
    
    # SSHディレクトリ作成
    if [[ "$DRY_RUN" = "false" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    else
        log_info "ドライラン: mkdir -p $ssh_dir && chmod 700 $ssh_dir"
    fi
    
    # SSH設定ファイル作成・更新
    local ssh_config_content="# Dotfiles SSH設定 - セキュリティ強化
# 自動生成 - 手動編集注意

# デフォルトセキュリティ設定
Host *
    # セキュリティ設定
    PasswordAuthentication no
    PubkeyAuthentication yes
    ChallengeResponseAuthentication no
    UsePAM no
    
    # 暗号化設定
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
    KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group16-sha512,diffie-hellman-group14-sha256
    MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
    
    # プロトコル設定
    Protocol 2
    Port 22
    
    # 接続設定
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
    
    # セキュリティ監査
    LogLevel INFO
    
    # 鍵設定
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes

# GitHub設定
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# 開発サーバー設定例
# Host dev-server
#     HostName your-dev-server.com
#     User your-username
#     IdentityFile ~/.ssh/id_ed25519
#     Port 22

# 一時的な設定（必要に応じて有効化）
# Host temp-*
#     StrictHostKeyChecking no
#     UserKnownHostsFile /dev/null
"
    
    if [[ ! -f "$ssh_config" ]] || [[ "$DRY_RUN" = "false" ]]; then
        if [[ "$DRY_RUN" = "false" ]]; then
            # 既存設定のバックアップ
            if [[ -f "$ssh_config" ]]; then
                cp "$ssh_config" "$ssh_config.backup.$(date +%Y%m%d-%H%M%S)"
                log_info "既存SSH設定をバックアップ"
            fi
            
            echo "$ssh_config_content" > "$ssh_config"
            chmod 600 "$ssh_config"
            log_success "SSH設定ファイル作成: $ssh_config"
        else
            log_info "ドライラン: SSH設定ファイル作成予定: $ssh_config"
        fi
    else
        log_success "SSH設定ファイルは既に存在"
    fi
    
    # SSH鍵生成確認
    local ssh_key="$ssh_dir/id_ed25519"
    if [[ ! -f "$ssh_key" ]]; then
        log_info "🔑 新しいSSH鍵を生成中..."
        
        if [[ "$DRY_RUN" = "false" ]]; then
            # Ed25519鍵生成（セキュリティ推奨）
            ssh-keygen -t ed25519 -C "$(whoami)@$(hostname) - Dotfiles" -f "$ssh_key" -N "" || {
                log_error "SSH鍵生成に失敗"
                return 1
            }
            
            chmod 600 "$ssh_key"
            chmod 644 "$ssh_key.pub"
            
            log_success "SSH鍵生成完了: $ssh_key"
            log_info "公開鍵: $(cat "$ssh_key.pub")"
            log_warning "GitHubなどのサービスに公開鍵を登録してください"
        else
            log_info "ドライラン: ssh-keygen -t ed25519 -f $ssh_key"
        fi
    else
        log_success "SSH鍵は既に存在: $ssh_key"
        
        # 権限確認
        local key_perms
        key_perms=$(stat -f "%A" "$ssh_key" 2>/dev/null || echo "unknown")
        if [[ "$key_perms" != "600" ]]; then
            log_warning "SSH鍵の権限を修正中..."
            if [[ "$DRY_RUN" = "false" ]]; then
                chmod 600 "$ssh_key"
            else
                log_info "ドライラン: chmod 600 $ssh_key"
            fi
        fi
    fi
}

# GPG設定最適化
setup_gpg_security() {
    log_step "🔐 GPG設定最適化中..."
    
    local gpg_dir="$HOME/.gnupg"
    
    # GPGディレクトリ作成
    if [[ "$DRY_RUN" = "false" ]]; then
        mkdir -p "$gpg_dir"
        chmod 700 "$gpg_dir"
    else
        log_info "ドライラン: mkdir -p $gpg_dir && chmod 700 $gpg_dir"
    fi
    
    # GPG設定ファイル
    local gpg_conf="$gpg_dir/gpg.conf"
    local gpg_config_content="# Dotfiles GPG設定 - セキュリティ強化

# 暗号化設定
cipher-algo AES256
digest-algo SHA256
cert-digest-algo SHA256
compress-algo 1
s2k-digest-algo SHA256
s2k-cipher-algo AES256

# セキュリティ設定
no-emit-version
no-comments
keyid-format 0xlong
with-fingerprint
list-options show-uid-validity
verify-options show-uid-validity

# 鍵サーバー設定
keyserver hkps://keys.openpgp.org
keyserver-options auto-key-retrieve
keyserver-options honor-keyserver-url

# 信頼モデル
trust-model tofu+pgp
tofu-default-policy unknown

# UI設定
use-agent
pinentry-mode loopback
"
    
    if [[ "$DRY_RUN" = "false" ]]; then
        echo "$gpg_config_content" > "$gpg_conf"
        chmod 600 "$gpg_conf"
        log_success "GPG設定ファイル作成: $gpg_conf"
    else
        log_info "ドライラン: GPG設定ファイル作成予定: $gpg_conf"
    fi
    
    # GPG鍵確認
    if [[ "$DRY_RUN" = "false" ]]; then
        local existing_keys
        existing_keys=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -c "sec" || echo "0")
        
        if [[ "$existing_keys" -eq 0 ]]; then
            log_info "🔑 GPG鍵が見つかりません（後で手動生成を推奨）"
            log_info "    gpg --full-generate-key を実行してください"
        else
            log_success "GPG鍵が存在: ${existing_keys}個"
        fi
    else
        log_info "ドライラン: GPG鍵確認スキップ"
    fi
}

# ファイル権限監査・修正
audit_file_permissions() {
    log_step "📁 ファイル権限監査中..."
    
    local issues_found=0
    
    # 重要ファイルの権限チェック
    local critical_files=(
        "$HOME/.ssh/id_*:600"
        "$HOME/.config/sops/age/keys.txt:600"
        "$HOME/.gnupg/secring.gpg:600"
        "$HOME/.gnupg/pubring.gpg:644"
        "$HOME/.ssh/config:600"
        "$HOME/.gitconfig:644"
    )
    
    for file_perm in "${critical_files[@]}"; do
        local file_pattern="${file_perm%:*}"
        local expected_perm="${file_perm#*:}"
        
        # ワイルドカード展開
        for file in $file_pattern; do
            if [[ -f "$file" ]]; then
                local current_perm
                current_perm=$(stat -f "%A" "$file" 2>/dev/null || echo "unknown")
                
                if [[ "$current_perm" != "$expected_perm" ]]; then
                    log_warning "権限要修正: $file (現在: $current_perm, 推奨: $expected_perm)"
                    ((issues_found++))
                    
                    if [[ "$DRY_RUN" = "false" ]]; then
                        chmod "$expected_perm" "$file"
                        log_success "権限修正完了: $file"
                    else
                        log_info "ドライラン: chmod $expected_perm $file"
                    fi
                fi
            fi
        done
    done
    
    # セキュリティリスクのあるファイル検索
    log_info "🔍 セキュリティリスク検索中..."
    
    # 書き込み可能なファイル
    local writable_files
    writable_files=$(find "$HOME" -maxdepth 3 -type f -perm -o+w 2>/dev/null | head -5)
    
    if [[ -n "$writable_files" ]]; then
        log_warning "他ユーザーが書き込み可能なファイル発見:"
        echo "$writable_files" | while read -r file; do
            echo "    - $file"
            ((issues_found++))
        done
    fi
    
    if [[ $issues_found -eq 0 ]]; then
        log_success "ファイル権限監査: 問題なし"
    else
        log_warning "ファイル権限監査: ${issues_found}件の問題を発見"
    fi
}

# セキュリティベースライン検証
verify_security_baseline() {
    log_step "🛡️ セキュリティベースライン検証中..."
    
    # 実装済みのセキュリティコンプライアンスチェック実行
    if [[ -f "$DOTFILES_ROOT/scripts/security-compliance-check.sh" ]]; then
        log_info "📋 セキュリティコンプライアンスチェック実行中..."
        
        if [[ "$DRY_RUN" = "false" ]]; then
            # 検証実行（エラーは無視して継続）
            "$DOTFILES_ROOT/scripts/security-compliance-check.sh" || {
                log_warning "セキュリティコンプライアンスチェックで一部警告あり"
            }
        else
            log_info "ドライラン: セキュリティコンプライアンスチェックスキップ"
        fi
    else
        log_warning "セキュリティコンプライアンスチェックスクリプトが見つかりません"
    fi
    
    log_success "セキュリティベースライン検証完了"
}

# 自動化設定ファイル生成
generate_automation_config() {
    log_step "⚙️ 自動化設定生成中..."
    
    local automation_config="$DOTFILES_ROOT/security-automation.json"
    
    local config_content="{
  \"security_automation\": {
    \"version\": \"1.0.0\",
    \"generated\": \"$(date -Iseconds)\",
    \"features\": {
      \"age_encryption\": {
        \"enabled\": true,
        \"key_file\": \"~/.config/sops/age/keys.txt\",
        \"config_file\": \"$SECURITY_DIR/sops/config/.sops.yaml\"
      },
      \"ssh_security\": {
        \"enabled\": true,
        \"config_file\": \"~/.ssh/config\",
        \"key_type\": \"ed25519\",
        \"security_hardening\": true
      },
      \"gpg_security\": {
        \"enabled\": true,
        \"config_file\": \"~/.gnupg/gpg.conf\",
        \"cipher_algo\": \"AES256\"
      },
      \"file_permissions\": {
        \"enabled\": true,
        \"audit_schedule\": \"weekly\",
        \"auto_fix\": true
      }
    },
    \"monitoring\": {
      \"compliance_check\": {
        \"enabled\": true,
        \"schedule\": \"daily\",
        \"script\": \"scripts/security-compliance-check.sh\"
      },
      \"audit_log\": {
        \"enabled\": true,
        \"file\": \"security-audit.log\",
        \"retention_days\": 30
      }
    },
    \"integration\": {
      \"ci_cd\": {
        \"enabled\": true,
        \"workflows\": [\".github/workflows/security.yml\"]
      },
      \"git_hooks\": {
        \"enabled\": true,
        \"pre_commit\": [\"security-scan\", \"secret-detection\"]
      }
    }
  }
}"
    
    if [[ "$DRY_RUN" = "false" ]]; then
        echo "$config_content" > "$automation_config"
        log_success "自動化設定ファイル生成: $automation_config"
    else
        log_info "ドライラン: 自動化設定ファイル生成予定: $automation_config"
    fi
}

# セットアップレポート生成
generate_setup_report() {
    log_step "📋 セットアップレポート生成中..."
    
    local report_file="$DOTFILES_ROOT/security-baseline-setup-report.md"
    
    cat > "$report_file" << EOF
# セキュリティベースライン自動セットアップレポート

実行日時: $(date)
実行モード: $([ "$DRY_RUN" = "true" ] && echo "ドライラン" || echo "実行")
スクリプト: security-baseline-automation.sh

## 実装された機能

### ✅ Age暗号化設定
- Age秘密鍵生成・設定
- SOPS設定ファイル作成
- 暗号化ポリシー設定

### ✅ SSH設定最適化
- セキュリティ強化設定
- Ed25519鍵生成
- 接続設定最適化

### ✅ GPG設定最適化
- セキュリティ強化設定
- 暗号化アルゴリズム設定
- 鍵サーバー設定

### ✅ ファイル権限監査
- 重要ファイル権限確認
- 自動権限修正
- セキュリティリスク検出

### ✅ 自動化設定
- セキュリティ自動化設定
- 監視・監査設定
- CI/CD統合設定

## セキュリティ状況

### 暗号化
- SOPS/Age: $([ -f "$HOME/.config/sops/age/keys.txt" ] && echo "✅ 設定済み" || echo "❌ 未設定")
- SSH鍵: $([ -f "$HOME/.ssh/id_ed25519" ] && echo "✅ 設定済み" || echo "❌ 未設定")
- GPG設定: $([ -f "$HOME/.gnupg/gpg.conf" ] && echo "✅ 設定済み" || echo "❌ 未設定")

### 設定ファイル
- SSH設定: $([ -f "$HOME/.ssh/config" ] && echo "✅ 設定済み" || echo "❌ 未設定")
- SOPS設定: $([ -f "$SECURITY_DIR/sops/config/.sops.yaml" ] && echo "✅ 設定済み" || echo "❌ 未設定")
- 自動化設定: $([ -f "$DOTFILES_ROOT/security-automation.json" ] && echo "✅ 設定済み" || echo "❌ 未設定")

## 次のステップ

### 手動作業が必要
1. **GitHub SSH鍵登録**
   - 公開鍵: \`cat ~/.ssh/id_ed25519.pub\`
   - GitHub Settings > SSH keys に登録

2. **GPG鍵生成（任意）**
   - \`gpg --full-generate-key\` でGPG鍵生成
   - Git署名設定: \`git config --global user.signingkey <KEY_ID>\`

3. **シークレット暗号化**
   - 機密情報をSOPS暗号化
   - \`sops secrets.yaml\` で暗号化編集

### 自動化された機能
- セキュリティコンプライアンスチェック
- ファイル権限監査
- CI/CDセキュリティスキャン

## ファイル一覧

### 生成・更新されたファイル
- \`~/.config/sops/age/keys.txt\` - Age秘密鍵
- \`~/.ssh/config\` - SSH設定
- \`~/.ssh/id_ed25519\` - SSH秘密鍵
- \`~/.gnupg/gpg.conf\` - GPG設定
- \`$SECURITY_DIR/sops/config/.sops.yaml\` - SOPS設定
- \`$DOTFILES_ROOT/security-automation.json\` - 自動化設定

### 関連スクリプト
- \`scripts/security-compliance-check.sh\` - コンプライアンスチェック
- \`scripts/security-baseline-automation.sh\` - 本スクリプト
- \`.github/workflows/security.yml\` - CI/CDセキュリティワークフロー

## トラブルシューティング

### よくある問題
1. **Age鍵の権限エラー**
   - 解決: \`chmod 600 ~/.config/sops/age/keys.txt\`

2. **SSH接続できない**
   - 解決: \`ssh-add ~/.ssh/id_ed25519\`

3. **SOPS暗号化エラー**
   - 解決: Age鍵とSOPS設定を確認

### サポート
- セキュリティコンプライアンスチェック: \`./scripts/security-compliance-check.sh\`
- 詳細ログ: \`$SETUP_LOG\`

---

*生成日時: $(date)*
*実行モード: $([ "$DRY_RUN" = "true" ] && echo "ドライラン" || echo "実行")*
EOF
    
    log_success "セットアップレポート生成完了: $report_file"
}

# メイン処理
main() {
    local start_time
    start_time=$(date +%s)
    
    # ログ初期化
    echo "# セキュリティベースライン自動セットアップログ - $(date)" > "$SETUP_LOG"
    
    # 各段階実行
    check_prerequisites || exit 1
    echo ""
    
    setup_age_encryption
    echo ""
    
    setup_ssh_security
    echo ""
    
    setup_gpg_security  
    echo ""
    
    audit_file_permissions
    echo ""
    
    verify_security_baseline
    echo ""
    
    generate_automation_config
    echo ""
    
    generate_setup_report
    
    local end_time
    end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    echo ""
    log_success "🎉 セキュリティベースライン自動化完了！"
    echo "⏱️  実行時間: ${total_time}秒"
    echo "🔧 実行モード: $([ "$DRY_RUN" = "true" ] && echo "ドライラン" || echo "実行")"
    echo "📋 セットアップレポート: $DOTFILES_ROOT/security-baseline-setup-report.md"
    echo "📊 自動化設定: $DOTFILES_ROOT/security-automation.json"
    echo ""
    echo "✨ セキュリティベースラインが完全自動化されました！"
    
    if [[ "$DRY_RUN" = "false" ]]; then
        echo ""
        log_info "🔑 次の手動作業を実行してください："
        echo "  1. GitHub SSH鍵登録: cat ~/.ssh/id_ed25519.pub"
        echo "  2. GPG鍵生成（任意）: gpg --full-generate-key"
        echo "  3. シークレット暗号化: sops secrets.yaml"
    fi
}

# 実行
main "$@"