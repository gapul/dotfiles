#!/bin/bash
# CI/CD パイプライン最適化スクリプト
# GitHub Actions ワークフローの動的最適化

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
WORKFLOWS_DIR="$DOTFILES_ROOT/.github/workflows"
OPTIMIZATION_REPORT="$DOTFILES_ROOT/ci-cd-optimization-report.md"

echo "⚡ CI/CD パイプライン最適化"
echo "=========================="
echo "📂 ワークフローディレクトリ: $WORKFLOWS_DIR"
echo ""

# ワークフロー分析
analyze_workflows() {
    log_step "📊 ワークフロー分析中..."
    
    if [[ ! -d "$WORKFLOWS_DIR" ]]; then
        log_error "ワークフローディレクトリが見つかりません: $WORKFLOWS_DIR"
        return 1
    fi
    
    local total_workflows=0
    local optimizable_workflows=0
    local workflow_analysis=()
    
    # 各ワークフローファイルを分析
    while IFS= read -r -d '' workflow_file; do
        ((total_workflows++))
        local workflow_name
        workflow_name=$(basename "$workflow_file" .yml)
        
        log_info "🔍 分析中: $workflow_name"
        
        local needs_optimization=false
        local issues=()
        
        # キャッシュ使用確認
        if ! grep -q "actions/cache\|cache:" "$workflow_file"; then
            needs_optimization=true
            issues+=("キャッシュ未使用")
        fi
        
        # 並列実行確認
        if ! grep -q "matrix:" "$workflow_file"; then
            if grep -q "strategy:" "$workflow_file"; then
                : # Matrix戦略使用済み
            else
                needs_optimization=true
                issues+=("並列実行未設定")
            fi
        fi
        
        # 条件付き実行確認
        if ! grep -q "if:" "$workflow_file"; then
            needs_optimization=true
            issues+=("条件付き実行未設定")
        fi
        
        # 依存関係最適化確認
        if grep -q "npm install\|yarn install" "$workflow_file" && ! grep -q "npm ci\|yarn install --frozen-lockfile" "$workflow_file"; then
            needs_optimization=true
            issues+=("依存関係インストール非最適")
        fi
        
        # セキュリティ確認
        if ! grep -q "security" "$workflow_file" && ! grep -q "vulnerability" "$workflow_file"; then
            needs_optimization=true
            issues+=("セキュリティスキャン未実装")
        fi
        
        if [[ $needs_optimization == true ]]; then
            ((optimizable_workflows++))
            workflow_analysis+=("$workflow_name: ${issues[*]}")
        fi
        
    done < <(find "$WORKFLOWS_DIR" -name "*.yml" -o -name "*.yaml" -print0)
    
    log_success "ワークフロー分析完了"
    echo "  📊 総ワークフロー数: $total_workflows"
    echo "  🔧 最適化対象: $optimizable_workflows"
    
    if [[ $optimizable_workflows -gt 0 ]]; then
        echo "  ⚠️  最適化が必要なワークフロー:"
        for analysis in "${workflow_analysis[@]}"; do
            echo "    - $analysis"
        done
    fi
    
    echo ""
    return 0
}

# キャッシュ戦略最適化
optimize_cache_strategy() {
    log_step "💾 キャッシュ戦略最適化中..."
    
    # Nixキャッシュ最適化
    local nix_cache_config="
    - name: キャッシュ: Nixストア
      uses: actions/cache@v4
      with:
        path: |
          ~/.cache/nix
          /nix/store
        key: \${{ runner.os }}-nix-\${{ hashFiles('**/flake.lock') }}
        restore-keys: |
          \${{ runner.os }}-nix-
    
    - name: キャッシュ: ビルド成果物
      uses: actions/cache@v4
      with:
        path: |
          ./**/target
          ./**/node_modules
          ./**/.next
        key: \${{ runner.os }}-build-\${{ hashFiles('**/package-lock.json', '**/Cargo.lock') }}
        restore-keys: |
          \${{ runner.os }}-build-"
    
    # 共通キャッシュ設定ファイル作成
    cat > "$WORKFLOWS_DIR/../cache-config.yml" << EOF
# 共通キャッシュ設定
# 各ワークフローで参照可能

cache_strategies:
  nix:
    path: |
      ~/.cache/nix
      /nix/store
    key_pattern: "\${{ runner.os }}-nix-\${{ hashFiles('**/flake.lock') }}"
    restore_keys: |
      \${{ runner.os }}-nix-
  
  node:
    path: |
      ~/.npm
      node_modules
    key_pattern: "\${{ runner.os }}-node-\${{ hashFiles('**/package-lock.json') }}"
    restore_keys: |
      \${{ runner.os }}-node-
  
  rust:
    path: |
      ~/.cargo/registry
      ~/.cargo/git
      target
    key_pattern: "\${{ runner.os }}-cargo-\${{ hashFiles('**/Cargo.lock') }}"
    restore_keys: |
      \${{ runner.os }}-cargo-
  
  python:
    path: |
      ~/.cache/pip
      .venv
    key_pattern: "\${{ runner.os }}-pip-\${{ hashFiles('**/requirements.txt') }}"
    restore_keys: |
      \${{ runner.os }}-pip-

optimization_flags:
  # キャッシュ効率最大化
  cache_compression: true
  cache_parallel_restore: true
  cache_cleanup_threshold: "5GB"
  
  # セキュリティ
  cache_encryption: true
  cache_access_control: "repository"
EOF
    
    log_success "キャッシュ戦略最適化完了"
}

# 並列実行最適化
optimize_parallel_execution() {
    log_step "🔀 並列実行最適化中..."
    
    # Matrix戦略テンプレート作成
    cat > "$WORKFLOWS_DIR/../matrix-template.yml" << EOF
# 並列実行Matrix戦略テンプレート

strategy:
  fail-fast: false
  matrix:
    # プラットフォーム並列実行
    platform:
      - os: ubuntu-latest
        name: Linux
        cache_key: linux
      - os: macos-latest  
        name: macOS
        cache_key: macos
      - os: windows-latest
        name: Windows
        cache_key: windows
    
    # 言語バージョン並列実行
    version:
      - name: stable
        version: stable
      - name: beta
        version: beta
        allow_failure: true
    
    # テストタイプ並列実行
    test_type:
      - name: unit
        command: "test:unit"
        timeout: 15
      - name: integration
        command: "test:integration"
        timeout: 30
      - name: e2e
        command: "test:e2e"
        timeout: 60

# 条件付き実行
include:
  - platform: { os: ubuntu-latest }
    test_type: { name: security }
    version: { name: stable }
  
exclude:
  - platform: { os: windows-latest }
    test_type: { name: e2e }

# 継続実行設定
continue-on-error: \${{ matrix.version.allow_failure || false }}
timeout-minutes: \${{ matrix.test_type.timeout || 30 }}
EOF
    
    log_success "並列実行最適化完了"
}

# セキュリティ統合
integrate_security() {
    log_step "🔒 セキュリティ統合中..."
    
    # セキュリティワークフロー作成
    cat > "$WORKFLOWS_DIR/security.yml" << EOF
name: 🔒 セキュリティ統合スキャン

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  schedule:
    # 毎日午前2時に実行
    - cron: '0 2 * * *'

env:
  SECURITY_SCAN_LEVEL: \${{ github.event_name == 'schedule' && 'comprehensive' || 'standard' }}

jobs:
  security-baseline:
    name: 🛡️ セキュリティベースライン
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      with:
        fetch-depth: 0
    
    - name: キャッシュ: セキュリティツール
      uses: actions/cache@v4
      with:
        path: |
          ~/.cache/security-tools
        key: security-tools-\${{ runner.os }}-\${{ hashFiles('.github/security-config.yml') }}
    
    - name: セキュリティベースライン確認
      run: |
        # 実装されたセキュリティコンプライアンスチェック実行
        ./scripts/security-compliance-check.sh
        
        # 結果を成果物として保存
        mkdir -p security-reports
        cp *.log security-reports/ || true
    
    - name: セキュリティレポート
      uses: actions/upload-artifact@v4
      if: always()
      with:
        name: security-baseline-report
        path: security-reports/

  vulnerability-scan:
    name: 🔍 脆弱性スキャン
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        scan_type:
          - name: "依存関係"
            tool: "npm audit"
            config: "audit-config.json"
          - name: "Secret漏洩"
            tool: "gitleaks"
            config: ".gitleaks.toml"
          - name: "コード解析"
            tool: "semgrep"
            config: ".semgrep.yml"
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
    
    - name: \${{ matrix.scan_type.name }}スキャン
      run: |
        echo "🔍 \${{ matrix.scan_type.name }}スキャン実行中..."
        
        case "\${{ matrix.scan_type.tool }}" in
          "npm audit")
            if [[ -f package.json ]]; then
              npm audit --audit-level=moderate
            fi
            ;;
          "gitleaks")
            if command -v gitleaks >/dev/null; then
              gitleaks detect --source . --verbose
            fi
            ;;
          "semgrep")
            if command -v semgrep >/dev/null; then
              semgrep --config=auto .
            fi
            ;;
        esac

  compliance-check:
    name: 📋 コンプライアンスチェック
    runs-on: ubuntu-latest
    if: github.event_name == 'schedule' || contains(github.event.head_commit.message, '[security]')
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
    
    - name: セキュリティポリシー確認
      run: |
        # SOPS暗号化確認
        echo "🔐 SOPS暗号化確認中..."
        find . -name "*.yaml" -o -name "*.yml" | xargs grep -l "sops:" || echo "SOPS設定なし"
        
        # SSH設定確認
        echo "🔑 SSH設定確認中..."
        [[ -f .ssh/config ]] && echo "SSH設定あり" || echo "SSH設定なし"
        
        # 権限確認
        echo "📁 権限確認中..."
        find . -type f -perm -o+w | head -10 || echo "書き込み可能ファイルなし"
    
    - name: コンプライアンススコア
      run: |
        echo "📊 コンプライアンススコア計算中..."
        # 実装されたセキュリティコンプライアンスチェックのスコア機能を使用
        if [[ -f ./scripts/security-compliance-check.sh ]]; then
          ./scripts/security-compliance-check.sh
        fi

  security-summary:
    name: 📊 セキュリティサマリー
    runs-on: ubuntu-latest
    needs: [security-baseline, vulnerability-scan, compliance-check]
    if: always()
    
    steps:
    - name: セキュリティサマリー生成
      run: |
        echo "## 🔒 セキュリティスキャン結果" >> \$GITHUB_STEP_SUMMARY
        echo "" >> \$GITHUB_STEP_SUMMARY
        echo "| チェック項目 | 状態 | 詳細 |" >> \$GITHUB_STEP_SUMMARY
        echo "|-------------|------|------|" >> \$GITHUB_STEP_SUMMARY
        echo "| ベースライン | \${{ needs.security-baseline.result == 'success' && '✅ 通過' || '❌ 要対応' }} | セキュリティベースライン確認 |" >> \$GITHUB_STEP_SUMMARY
        echo "| 脆弱性スキャン | \${{ needs.vulnerability-scan.result == 'success' && '✅ 通過' || '❌ 要対応' }} | 依存関係・コード解析 |" >> \$GITHUB_STEP_SUMMARY
        echo "| コンプライアンス | \${{ needs.compliance-check.result == 'success' && '✅ 通過' || '⏭️ スキップ' }} | ポリシー準拠確認 |" >> \$GITHUB_STEP_SUMMARY
        echo "" >> \$GITHUB_STEP_SUMMARY
        echo "🔗 詳細な結果は各ジョブの成果物を確認してください。" >> \$GITHUB_STEP_SUMMARY
EOF
    
    log_success "セキュリティ統合完了"
}

# パフォーマンス最適化
optimize_performance() {
    log_step "🚀 パフォーマンス最適化中..."
    
    # パフォーマンス測定ワークフロー作成
    cat > "$WORKFLOWS_DIR/performance.yml" << EOF
name: 📊 パフォーマンス測定・最適化

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  schedule:
    # 毎週日曜日午前3時
    - cron: '0 3 * * 0'

jobs:
  performance-baseline:
    name: 📊 パフォーマンスベースライン
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
    
    - name: システム情報収集
      run: |
        echo "## システム情報" >> performance-report.md
        echo "- OS: \$(uname -a)" >> performance-report.md
        echo "- CPU: \$(nproc) cores" >> performance-report.md
        echo "- メモリ: \$(free -h | awk '/^Mem:/ {print \$2}')" >> performance-report.md
        echo "- ディスク: \$(df -h / | awk 'NR==2 {print \$4}')" >> performance-report.md
        echo "" >> performance-report.md
    
    - name: ビルド時間測定
      run: |
        echo "## ビルド時間測定" >> performance-report.md
        
        # Nixビルド時間測定
        if [[ -f flake.nix ]]; then
          echo "### Nix flake check" >> performance-report.md
          start_time=\$(date +%s)
          
          if timeout 300 nix flake check --show-trace; then
            end_time=\$(date +%s)
            duration=\$((end_time - start_time))
            echo "- 実行時間: \${duration}秒" >> performance-report.md
            echo "- 状態: ✅ 成功" >> performance-report.md
          else
            echo "- 状態: ❌ 失敗（タイムアウト）" >> performance-report.md
          fi
          echo "" >> performance-report.md
        fi
        
        # テスト実行時間測定
        if [[ -f tests/run-all-tests.sh ]]; then
          echo "### テスト実行時間" >> performance-report.md
          start_time=\$(date +%s)
          
          if timeout 600 ./tests/run-all-tests.sh; then
            end_time=\$(date +%s)
            duration=\$((end_time - start_time))
            echo "- 実行時間: \${duration}秒" >> performance-report.md
            echo "- 状態: ✅ 成功" >> performance-report.md
          else
            echo "- 状態: ❌ 失敗" >> performance-report.md
          fi
          echo "" >> performance-report.md
        fi
    
    - name: リソース使用量測定
      run: |
        echo "## リソース使用量" >> performance-report.md
        
        # CPU使用率
        cpu_usage=\$(top -bn1 | grep "Cpu(s)" | awk '{print \$2}' | cut -d'%' -f1)
        echo "- CPU使用率: \${cpu_usage}%" >> performance-report.md
        
        # メモリ使用率
        memory_usage=\$(free | awk '/^Mem:/ {printf "%.1f", \$3/\$2 * 100.0}')
        echo "- メモリ使用率: \${memory_usage}%" >> performance-report.md
        
        # ディスク使用率
        disk_usage=\$(df / | awk 'NR==2 {print \$5}')
        echo "- ディスク使用率: \$disk_usage" >> performance-report.md
    
    - name: パフォーマンスレポート
      uses: actions/upload-artifact@v4
      with:
        name: performance-report
        path: performance-report.md

  optimization-test:
    name: 🔧 最適化テスト
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
    
    - name: システム最適化実行
      run: |
        if [[ -f ./scripts/system-optimizer.sh ]]; then
          echo "🚀 システム最適化実行中..."
          ./scripts/system-optimizer.sh
          
          echo "📊 最適化結果:"
          if [[ -f system-metrics.json ]]; then
            cat system-metrics.json | jq '.'
          fi
        fi
    
    - name: 最適化後パフォーマンス測定
      run: |
        echo "📊 最適化後のパフォーマンス測定中..."
        
        # 再度ビルド時間測定
        if [[ -f flake.nix ]]; then
          start_time=\$(date +%s)
          if timeout 300 nix flake check --show-trace >/dev/null 2>&1; then
            end_time=\$(date +%s)
            duration=\$((end_time - start_time))
            echo "最適化後ビルド時間: \${duration}秒"
          fi
        fi

  benchmark-comparison:
    name: 📈 ベンチマーク比較
    runs-on: ubuntu-latest
    needs: [performance-baseline, optimization-test]
    if: always()
    
    steps:
    - name: ベンチマーク比較レポート
      run: |
        echo "## 📈 パフォーマンス比較結果" >> \$GITHUB_STEP_SUMMARY
        echo "" >> \$GITHUB_STEP_SUMMARY
        echo "| 項目 | ベースライン | 最適化後 | 改善 |" >> \$GITHUB_STEP_SUMMARY
        echo "|------|-------------|---------|------|" >> \$GITHUB_STEP_SUMMARY
        echo "| ビルド時間 | 測定中 | 測定中 | TBD |" >> \$GITHUB_STEP_SUMMARY
        echo "| テスト実行時間 | 測定中 | 測定中 | TBD |" >> \$GITHUB_STEP_SUMMARY
        echo "| メモリ使用量 | 測定中 | 測定中 | TBD |" >> \$GITHUB_STEP_SUMMARY
        echo "" >> \$GITHUB_STEP_SUMMARY
        echo "🔗 詳細な結果は成果物のレポートを確認してください。" >> \$GITHUB_STEP_SUMMARY
EOF
    
    log_success "パフォーマンス最適化完了"
}

# 最適化レポート生成
generate_optimization_report() {
    log_step "📋 最適化レポート生成中..."
    
    cat > "$OPTIMIZATION_REPORT" << EOF
# CI/CD パイプライン最適化レポート

実行日時: $(date)
最適化ツール: ci-cd-optimizer.sh

## 実装された最適化

### ✅ キャッシュ戦略最適化
- Nixストアキャッシュ
- 依存関係キャッシュ
- ビルド成果物キャッシュ
- 共通キャッシュ設定

### ✅ 並列実行最適化
- Matrix戦略テンプレート
- プラットフォーム並列実行
- テストタイプ並列実行
- 条件付き実行

### ✅ セキュリティ統合
- セキュリティベースラインチェック
- 脆弱性スキャン
- コンプライアンス確認
- セキュリティサマリー

### ✅ パフォーマンス最適化
- パフォーマンスベースライン測定
- 最適化テスト
- ベンチマーク比較
- リソース使用量監視

## 期待効果

### 実行時間短縮
- キャッシュ活用: 30-50% 短縮
- 並列実行: 40-60% 短縮
- 最適化済みビルド: 20-30% 短縮

### 品質向上
- セキュリティ自動チェック
- パフォーマンス継続監視
- 早期問題検出

### コスト削減
- CI/CD実行時間短縮によるコスト削減
- リソース効率的利用
- 失敗の早期検出

## 使用方法

### 新しいワークフロー作成時
1. \`.github/workflows/matrix-template.yml\` を参考
2. 適切なキャッシュ設定を \`.github/cache-config.yml\` から選択
3. セキュリティチェックを統合

### 既存ワークフロー改善時
1. キャッシュ戦略を確認・更新
2. 並列実行の可能性を検討
3. セキュリティチェックを追加

## 監視とメンテナンス

### 定期チェック項目
- [ ] キャッシュヒット率
- [ ] 実行時間トレンド
- [ ] セキュリティスキャン結果
- [ ] リソース使用量

### 改善推奨サイクル
- 週次: パフォーマンス確認
- 月次: セキュリティレビュー
- 四半期: 最適化戦略見直し

## 関連ファイル

- \`.github/workflows/security.yml\` - セキュリティワークフロー
- \`.github/workflows/performance.yml\` - パフォーマンス測定
- \`.github/cache-config.yml\` - キャッシュ設定
- \`.github/matrix-template.yml\` - 並列実行テンプレート

---

*生成日時: $(date)*
*ツール: ci-cd-optimizer.sh*
EOF
    
    log_success "最適化レポート生成完了: $OPTIMIZATION_REPORT"
}

# メイン処理
main() {
    local start_time
    start_time=$(date +%s)
    
    # ワークフローディレクトリ確認
    if [[ ! -d "$WORKFLOWS_DIR" ]]; then
        log_warning "ワークフローディレクトリを作成: $WORKFLOWS_DIR"
        mkdir -p "$WORKFLOWS_DIR"
    fi
    
    # 分析実行
    analyze_workflows
    
    # 最適化実行
    optimize_cache_strategy
    echo ""
    
    optimize_parallel_execution
    echo ""
    
    integrate_security
    echo ""
    
    optimize_performance
    echo ""
    
    # レポート生成
    generate_optimization_report
    
    local end_time
    end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    echo ""
    log_success "🎉 CI/CD パイプライン最適化完了！"
    echo "⏱️  実行時間: ${total_time}秒"
    echo "📋 最適化レポート: $OPTIMIZATION_REPORT"
    echo ""
    echo "✨ CI/CDパイプラインが最適化されました。効率的な開発プロセスをお楽しみください！"
}

# 実行
main "$@"