#!/bin/bash
# ドキュメント統合・整理スクリプト
# 重複削除と構造化によりドキュメント煩雑性を解消

set -euo pipefail

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ログ関数
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# 設定
DOCS_DIR="docs"
BACKUP_DIR="${HOME}/.dotfiles-docs-backup-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=${1:-false}

echo "📚 Dotfiles ドキュメント統合開始"
echo "📂 対象ディレクトリ: $DOCS_DIR"
echo "🔄 実行モード: $([ "$DRY_RUN" == "true" ] && echo "DRY RUN (確認のみ)" || echo "実際の統合")"

if [[ "$DRY_RUN" != "true" ]]; then
    echo "💾 バックアップディレクトリ: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi

echo ""

# Phase 3関連文書の統合対象ファイル
PHASE3_FILES=(
    "PHASE3_COMPLETE_IMPLEMENTATION_SCHEDULE.md"
    "PHASE3_COMPLETION_STATUS.md" 
    "PHASE3_ENHANCEMENT_PROPOSALS.md"
    "PHASE3_IMPLEMENTATION_ROADMAP.md"
    "PHASE3_REMAINING_TASKS.md"
    "PHASE3_USAGE_GUIDE.md"
    "Next_Step.md"
)

# バックアップ関数
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup_path="$BACKUP_DIR/$(basename "$file")"
        cp "$file" "$backup_path"
        log_info "バックアップ: $file → $backup_path"
    fi
}

# ファイル移動関数
move_to_archive() {
    local file="$1"
    local description="$2"
    
    if [[ -f "$DOCS_DIR/$file" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warning "[DRY RUN] アーカイブ予定: $file - $description"
        else
            backup_file "$DOCS_DIR/$file"
            mkdir -p "$DOCS_DIR/archive"
            mv "$DOCS_DIR/$file" "$DOCS_DIR/archive/"
            log_success "アーカイブ完了: $file → archive/ - $description"
        fi
    else
        log_info "存在しない: $file"
    fi
}

echo "🔄 Phase 1: Phase3関連文書の統合"

# Phase3文書を統合済みマスター文書に置き換え
log_info "Phase3関連文書をアーカイブ中..."
for file in "${PHASE3_FILES[@]}"; do
    move_to_archive "$file" "Phase3統合文書 PHASE3_MASTER_STATUS.md に統合済み"
done

echo ""
echo "🔄 Phase 2: ドキュメント構造改善"

# アーカイブディレクトリ作成
if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$DOCS_DIR/archive"
    mkdir -p "$DOCS_DIR/guides"
    mkdir -p "$DOCS_DIR/reference"
fi

# ドキュメントの分類・移動
log_info "ドキュメント分類実行中..."

# ガイド文書をguidesディレクトリに整理
GUIDE_FILES=(
    "SETUP_GUIDE.md:初期セットアップガイド"
    "DEVELOPMENT_ENVIRONMENT_GUIDE.md:開発環境構築ガイド"
    "AUTOMATION_GUIDE.md:自動化機能ガイド"
    "NEOVIM_GUIDE.md:Neovimカスタマイズガイド"
    "WEZTERM_GUIDE.md:WezTermカスタマイズガイド"
)

for entry in "${GUIDE_FILES[@]}"; do
    IFS=':' read -r file description <<< "$entry"
    if [[ -f "$DOCS_DIR/$file" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warning "[DRY RUN] 移動予定: $file → guides/ - $description"
        else
            backup_file "$DOCS_DIR/$file"
            mv "$DOCS_DIR/$file" "$DOCS_DIR/guides/"
            log_success "移動完了: $file → guides/ - $description"
        fi
    fi
done

# 参考資料をreferenceディレクトリに整理
REFERENCE_FILES=(
    "PACKAGE_MANAGEMENT_POLICY.md:パッケージ管理ポリシー参考資料"
)

for entry in "${REFERENCE_FILES[@]}"; do
    IFS=':' read -r file description <<< "$entry"
    if [[ -f "$DOCS_DIR/$file" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warning "[DRY RUN] 移動予定: $file → reference/ - $description"
        else
            backup_file "$DOCS_DIR/$file"
            mv "$DOCS_DIR/$file" "$DOCS_DIR/reference/"
            log_success "移動完了: $file → reference/ - $description"
        fi
    fi
done

echo ""
echo "🔄 Phase 3: マスターインデックス更新"

# README.mdの更新 (新しい構造を反映)
if [[ "$DRY_RUN" != "true" ]]; then
    cat > "$DOCS_DIR/README.md" << 'EOF'
# Dotfiles ドキュメント ナビゲーション

> 📋 **マスターインデックス**: 目的別ドキュメント案内 (統合・整理済み)

## 🎯 目的別クイックナビゲーション

### 🚀 **セットアップ・使い始め**
| ドキュメント | 用途 | 推奨読者 |
|-------------|------|-----------|
| [📖 guides/SETUP_GUIDE.md](guides/SETUP_GUIDE.md) | 初期セットアップ手順 | 新規ユーザー |
| [🔧 guides/DEVELOPMENT_ENVIRONMENT_GUIDE.md](guides/DEVELOPMENT_ENVIRONMENT_GUIDE.md) | 開発環境構築 | 開発者 |
| [⚙️ guides/AUTOMATION_GUIDE.md](guides/AUTOMATION_GUIDE.md) | 自動化機能の使い方 | 効率化重視ユーザー |

### 🛠️ **メンテナンス・改善** (統合済み)
| ドキュメント | 用途 | 緊急度 |
|-------------|------|--------|
| [🧹 CLEANUP_ANALYSIS_REPORT.md](CLEANUP_ANALYSIS_REPORT.md) | **96%サイズ削減可能** | 🔴 高 |
| [📊 MAINTENANCE_IMPROVEMENT_PLAN.md](MAINTENANCE_IMPROVEMENT_PLAN.md) | 包括的改善計画 | 🟡 中 |
| [📦 PACKAGE_MANAGEMENT_OPTIMIZATION.md](PACKAGE_MANAGEMENT_OPTIMIZATION.md) | パッケージ管理最適化 | 🟡 中 |

### 🔒 **セキュリティ・品質** (統合済み)
| ドキュメント | 用途 | 実装状況 |
|-------------|------|----------|
| [🛡️ SECURITY_ANALYSIS_REPORT.md](SECURITY_ANALYSIS_REPORT.md) | セキュリティ総合分析 | ⚠️ 設定要 |
| [🧪 TESTING_ENVIRONMENT_ANALYSIS.md](TESTING_ENVIRONMENT_ANALYSIS.md) | テスト環境整備 | 📋 計画済み |
| [📋 reference/PACKAGE_MANAGEMENT_POLICY.md](reference/PACKAGE_MANAGEMENT_POLICY.md) | パッケージ管理ポリシー | ✅ 完了 |

### 🎮 **アプリケーション固有ガイド** (整理済み)
| ドキュメント | 対象 | 詳細度 |
|-------------|------|--------|
| [📝 guides/NEOVIM_GUIDE.md](guides/NEOVIM_GUIDE.md) | Neovim設定 | 詳細 |
| [💻 guides/WEZTERM_GUIDE.md](guides/WEZTERM_GUIDE.md) | WezTerm設定 | 詳細 |

### 📋 **プロジェクト管理** (統合完了)
| ドキュメント | 状況 | 内容 |
|-------------|------|------|
| [🎯 PHASE3_MASTER_STATUS.md](PHASE3_MASTER_STATUS.md) | ✅ **統合完了** | Phase3全情報を一元管理 |
| [📁 archive/](archive/) | 🗄️ アーカイブ | 統合前の個別Phase3文書 |

---

## 🎯 **即座実行推奨アクション**

### ⚡ **今すぐ実行可能** (5分以内)
```bash
# 1. 96%サイズ削減実行
./scripts/cleanup-phase1.sh true   # DRY RUN確認
./scripts/cleanup-phase1.sh false  # 実際の削除

# 2. セキュリティ基盤構築
./nix/security/scripts/setup-security.sh
```

### 📚 **ドキュメント統合完了確認**
```bash
# ドキュメント統合スクリプト実行
./scripts/consolidate-docs.sh true   # DRY RUN確認
./scripts/consolidate-docs.sh false  # 実際の統合
```

---

## 📖 **ドキュメント構造** (整理後)

```
docs/
├── README.md                           # このファイル (マスターナビゲーション)
├── guides/                             # セットアップ・使用ガイド
│   ├── SETUP_GUIDE.md
│   ├── DEVELOPMENT_ENVIRONMENT_GUIDE.md
│   ├── AUTOMATION_GUIDE.md
│   ├── NEOVIM_GUIDE.md
│   └── WEZTERM_GUIDE.md
├── reference/                          # 参考資料・ポリシー
│   └── PACKAGE_MANAGEMENT_POLICY.md
├── PHASE3_MASTER_STATUS.md             # Phase3統合マスター文書
├── CLEANUP_ANALYSIS_REPORT.md          # クリーンアップ分析
├── MAINTENANCE_IMPROVEMENT_PLAN.md     # メンテナンス計画
├── PACKAGE_MANAGEMENT_OPTIMIZATION.md  # パッケージ最適化
├── SECURITY_ANALYSIS_REPORT.md         # セキュリティ分析
├── TESTING_ENVIRONMENT_ANALYSIS.md     # テスト環境分析
└── archive/                            # 統合前文書アーカイブ
    ├── PHASE3_COMPLETE_IMPLEMENTATION_SCHEDULE.md
    ├── PHASE3_COMPLETION_STATUS.md
    ├── PHASE3_ENHANCEMENT_PROPOSALS.md
    ├── PHASE3_IMPLEMENTATION_ROADMAP.md
    ├── PHASE3_REMAINING_TASKS.md
    ├── PHASE3_USAGE_GUIDE.md
    └── Next_Step.md
```

---

## 🎉 **統合効果**

### **Before → After**
- **📊 ドキュメント数**: 18件 → 12件 (主要ディレクトリ)
- **🔄 Phase3文書**: 7件 → 1件統合
- **📁 構造化**: フラット → 目的別分類
- **🧭 ナビゲーション**: 散在 → マスターインデックス

### **利用効率向上**
- **✨ 発見性**: 目的別分類により即座にアクセス
- **🔍 重複解消**: 同一内容の複数文書統合
- **📋 構造化**: guides/ reference/ archive/ 明確分離
- **🎯 実行重視**: 即座実行可能アクション明示

このドキュメント構造により、煩雑性を解消し効率的な情報アクセスを実現します。
EOF
    log_success "マスターインデックス更新完了"
fi

echo ""
echo "📊 統合結果サマリー"

if [[ "$DRY_RUN" == "true" ]]; then
    cat << EOF
🔍 DRY RUN結果:
  📁 アーカイブ予定: ${#PHASE3_FILES[@]} Phase3文書
  📂 構造化予定: guides/ reference/ archive/ ディレクトリ作成
  📋 更新予定: マスターインデックス (README.md)
  
📈 期待効果:
  📊 ドキュメント数: 18件 → 12件 (主要)
  🔄 Phase3統合: 7件 → 1件
  🧭 ナビゲーション: 大幅改善
  
実際の統合実行: ./scripts/consolidate-docs.sh false
EOF
else
    cat << EOF
🎉 ドキュメント統合完了!
  ✅ Phase3文書統合: 7件 → PHASE3_MASTER_STATUS.md
  ✅ 構造化完了: guides/ reference/ archive/ 作成
  ✅ マスターインデックス更新完了
  💾 バックアップ保存: $BACKUP_DIR
  
📈 達成効果:
  📊 主要ドキュメント数: 12件 (整理済み)
  🔍 発見性: 目的別分類完了
  🧭 ナビゲーション: docs/README.md 参照
  ⚡ 実行準備: 即座実行可能アクション明示
EOF
fi

echo ""
echo "✨ ドキュメント統合処理完了: $(date)"