# Dotfiles ドキュメント統合ナビゲーション

## 📚 ドキュメント構造

### 🚀 クイックスタート
- **[セットアップガイド](quick-start/SETUP_QUICK_START.md)** - 最短でdotfilesを導入
- **[メンテナンスガイド](quick-start/MAINTENANCE_QUICK_REFERENCE.md)** - 日常的な操作方法
- **[トラブルシューティング](quick-start/TROUBLESHOOTING_QUICK.md)** - よくある問題と解決法

### 🎯 包括的ガイド
- **[開発環境ガイド](guides/DEVELOPMENT_ENVIRONMENT_GUIDE.md)** - 開発環境の詳細設定
- **[自動化ガイド](guides/AUTOMATION_GUIDE.md)** - 自動化機能の使用方法
- **[Neovim設定ガイド](guides/comprehensive/NEOVIM_ADVANCED_CONFIG.md)** - Neovim高度設定
- **[WeztermガイドC](guides/WEZTERM_GUIDE.md)** - ターミナル詳細設定

### 🏗️ システム設計
- **[セキュリティマスター](systems/SECURITY_MASTER.md)** - セキュリティ総合管理
- **[テストマスター](systems/TESTING_MASTER.md)** - テスト環境総合管理
- **[システムヘルスモニタリング](systems/SYSTEM_HEALTH_MONITORING.md)** - システム監視
- **[メンテナンス自動化](systems/MAINTENANCE_AUTOMATION.md)** - メンテナンス自動化

### 📋 リファレンス
- **[パッケージ管理ポリシー](reference/PACKAGE_MANAGEMENT_POLICY.md)** - パッケージ管理方針

### 🔄 実装レポート
- **[Phase 3 実装概要](IMPLEMENTATION_SUMMARY.md)** - Phase 3完了レポート
- **[Phase 4 最適化レポート](PHASE4_SYSTEM_OPTIMIZATION_SUMMARY.md)** - システム最適化完了レポート
- **[パッケージ管理最適化](PACKAGE_MANAGEMENT_OPTIMIZATION.md)** - パッケージ管理改善

## 🎯 用途別ナビゲーション

### 🚀 **初めて使用する方**
1. **[セットアップクイックスタート](quick-start/SETUP_QUICK_START.md)** - 最初に読む
2. **[開発環境ガイド](guides/DEVELOPMENT_ENVIRONMENT_GUIDE.md)** - 環境構築詳細
3. **[トラブルシューティング](quick-start/TROUBLESHOOTING_QUICK.md)** - 問題解決

### 🔧 **既存ユーザー（メンテナンス）**
1. **[メンテナンスクイックリファレンス](quick-start/MAINTENANCE_QUICK_REFERENCE.md)** - 日常操作
2. **[システムヘルスモニタリング](systems/SYSTEM_HEALTH_MONITORING.md)** - 状態確認
3. **[メンテナンス自動化](systems/MAINTENANCE_AUTOMATION.md)** - 自動化機能

### 🏗️ **システム管理者**
1. **[セキュリティマスター](systems/SECURITY_MASTER.md)** - セキュリティ管理
2. **[テストマスター](systems/TESTING_MASTER.md)** - テスト環境管理
3. **[パッケージ管理ポリシー](reference/PACKAGE_MANAGEMENT_POLICY.md)** - パッケージ方針

### 🚀 **パフォーマンス最適化**
1. **[Phase 4 最適化レポート](PHASE4_SYSTEM_OPTIMIZATION_SUMMARY.md)** - システム最適化
2. **[パッケージ管理最適化](PACKAGE_MANAGEMENT_OPTIMIZATION.md)** - パッケージ最適化
3. **[システムヘルスモニタリング](systems/SYSTEM_HEALTH_MONITORING.md)** - 監視設定

### 📝 **カスタマイズ**
1. **[Neovim高度設定](guides/comprehensive/NEOVIM_ADVANCED_CONFIG.md)** - エディター設定
2. **[Weztermガイド](guides/WEZTERM_GUIDE.md)** - ターミナル設定
3. **[自動化ガイド](guides/AUTOMATION_GUIDE.md)** - 自動化設定

## 🔧 主要スクリプト

### システム最適化
```bash
# 統合システム最適化
./scripts/system-optimizer.sh

# CI/CD最適化
./scripts/ci-cd-optimizer.sh

# セキュリティベースライン自動化
./scripts/security-baseline-automation.sh
```

### パッケージ管理
```bash
# パッケージ分析
./scripts/unified-package-manager.sh analyze

# パッケージ競合確認
./scripts/unified-package-manager.sh conflicts

# パッケージ更新
./scripts/unified-package-manager.sh update
```

### セキュリティ
```bash
# セキュリティコンプライアンスチェック
./scripts/security-compliance-check.sh

# セキュリティベースライン自動化（ドライラン）
DRY_RUN=true ./scripts/security-baseline-automation.sh
```

### テスト
```bash
# 全テスト実行
./tests/run-all-tests.sh

# 単体テスト
./tests/unit/nix/platform-detection.test.sh

# 統合テスト
./tests/integration/deployment-test.sh
```

## 📊 システム状況確認

### 基本情報
```bash
# プラットフォーム情報
nix eval .#platformInfo --json

# システムヘルス
just health

# テスト状況
just test
```

### パフォーマンス
```bash
# システム最適化状況
./scripts/system-optimizer.sh

# パッケージ分析
./scripts/unified-package-manager.sh analyze

# CI/CD最適化状況
./scripts/ci-cd-optimizer.sh
```

### セキュリティ
```bash
# セキュリティコンプライアンス
./scripts/security-compliance-check.sh

# セキュリティベースライン状況
./scripts/security-baseline-automation.sh
```

## 🎯 レベル別推奨読書順序

### 🟢 **初心者レベル**
1. [セットアップクイックスタート](quick-start/SETUP_QUICK_START.md)
2. [メンテナンスクイックリファレンス](quick-start/MAINTENANCE_QUICK_REFERENCE.md)
3. [トラブルシューティング](quick-start/TROUBLESHOOTING_QUICK.md)

### 🟡 **中級レベル**
1. [開発環境ガイド](guides/DEVELOPMENT_ENVIRONMENT_GUIDE.md)
2. [自動化ガイド](guides/AUTOMATION_GUIDE.md)
3. [システムヘルスモニタリング](systems/SYSTEM_HEALTH_MONITORING.md)

### 🔴 **上級レベル**
1. [セキュリティマスター](systems/SECURITY_MASTER.md)
2. [テストマスター](systems/TESTING_MASTER.md)
3. [Phase 4 最適化レポート](PHASE4_SYSTEM_OPTIMIZATION_SUMMARY.md)

## 🔄 更新履歴

### 最新更新
- **2025年7月9日**: Phase 4システム最適化完了
- **2025年7月9日**: Phase 3包括的改善完了
- **2025年7月8日**: セキュリティマスター統合

### 主要マイルストーン
- ✅ **Phase 3**: パッケージ管理・セキュリティ・テスト統合
- ✅ **Phase 4**: システム最適化・CI/CD改善・セキュリティ自動化
- 🔄 **継続中**: ドキュメント統合・ナビゲーション改善

## 🆘 困ったときは

### 即座に解決したい
1. **[トラブルシューティング](quick-start/TROUBLESHOOTING_QUICK.md)** - よくある問題
2. **[メンテナンスクイックリファレンス](quick-start/MAINTENANCE_QUICK_REFERENCE.md)** - 基本操作

### 詳しく理解したい
1. **該当するシステムドキュメント** - 詳細な説明
2. **実装レポート** - 技術的詳細
3. **リファレンス** - 仕様・ポリシー

### 問題を報告したい
1. **GitHub Issues** - バグ報告・機能要求
2. **セキュリティ問題** - セキュリティ関連は別途報告
3. **改善提案** - 機能改善・最適化提案

---

*最終更新: 2025年7月9日*
*Phase 4完了 - システム最適化・CI/CD改善・セキュリティ自動化*