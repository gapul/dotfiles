# Phase 3 システム使用ガイド

**作成日**: 2025年7月2日  
**対象**: Phase 3 完成済み機能 (3.1-3.6)  
**ユーザー**: 開発者・システム管理者

## 🚀 クイックスタート

### システム有効化
```bash
# Nix設定でコンテキストシステムを有効化
dotfiles.context = {
  enable = true;
  profile = "full";  # minimal, standard, full
};

# 設定再構築
just rebuild  # または nix run nix-darwin -- switch --flake .
```

### 基本使用方法
```bash
# 1. プロジェクト検出
context-detect-project

# 2. 環境認識
context-detect-environment

# 3. リソース監視
context-monitor-resources status

# 4. テーマ自動調整
context-adapt-theme auto

# 5. ツール設定最適化
context-configure-tools auto

# 6. 電力管理
context-manage-power auto
```

## 📋 機能別使用方法

### 🎯 プロジェクト検出システム

#### 基本コマンド
```bash
# プロジェクト情報の検出
context-detect-project detect

# 詳細分析
context-detect-project analyze

# プロジェクト履歴表示
context-detect-project history
```

#### 出力例
```
🎯 Project Detection System
===========================
Action: detect
⏰ Detection time: 2025-07-02 21:00

📁 Project Analysis:
  🎯 Project type: nodejs (confidence: 95%)
  💻 Languages: javascript, typescript
  🚀 Framework: nextjs (confidence: 90%)
  📊 Project scale: medium (15 files, 2.5MB)
  🔄 Development phase: development

📦 Dependencies detected:
  📋 Framework dependencies: 8
  🧪 Development dependencies: 12
  🔧 Build tools: webpack, babel, eslint

💡 Recommendations:
  • Enable TypeScript strict mode
  • Configure ESLint for React hooks
  • Set up automated testing
```

#### プロジェクトテンプレート管理
```bash
# テンプレート一覧
context-project-templates list

# 新しいプロジェクト作成
context-project-templates create react-app my-project

# カスタムテンプレート追加
context-project-templates add my-template ./template-dir
```

### 🌍 環境認識システム

#### 環境検出
```bash
# 完全な環境分析
context-detect-environment detect

# 特定項目のみ
context-detect-environment time      # 時間コンテキスト
context-detect-environment location  # 場所検出
context-detect-environment situation # 状況分析
```

#### 場所パターン学習
```bash
# 現在の場所を学習
context-learn-location home

# 学習済み場所一覧
context-learn-location "" list

# 場所パターン削除
context-learn-location office remove
```

#### 作業パターン分析
```bash
# 過去7日間の分析
context-analyze-patterns summary

# 詳細分析（時間別）
context-analyze-patterns detailed

# CSV形式でエクスポート
context-analyze-patterns export
```

### 🔋 リソース監視システム

#### リソース状態確認
```bash
# 現在の状態
context-monitor-resources status

# 詳細監視
context-monitor-resources monitor

# 継続監視（10秒間）
context-monitor-resources continuous 10

# アラートのみ確認
context-monitor-resources alert
```

#### 出力例
```
📋 Resource Summary:
  🔋 Battery: 85% (charging)
  🖥️  CPU: 25% (light)
  💾 Memory: 45% used (moderate)
  🌐 Network: excellent (online)
  💿 Storage: 15% used (excellent)
  📊 Health: excellent (100/100)
```

#### リソース最適化
```bash
# 全体最適化
context-optimize-resources all

# バッテリー最適化
context-optimize-resources battery

# CPU最適化
context-optimize-resources cpu

# メモリ最適化
context-optimize-resources memory
```

### 🎨 テーマ自動調整システム

#### テーマ自動調整
```bash
# 自動検出・調整
context-adapt-theme auto

# 特定コンテキスト優先
context-adapt-theme auto focus     # 集中度優先
context-adapt-theme auto fatigue   # 疲労度優先
context-adapt-theme auto time      # 時間ベース

# 強制適用
context-adapt-theme auto current true
```

#### テーマ状態確認
```bash
# 現在の状態
context-adapt-theme status

# システムデフォルトにリセット
context-adapt-theme reset
```

#### テーマ分析
```bash
# 使用パターン分析
context-analyze-themes patterns

# 最適化提案
context-analyze-themes recommendations
```

#### テーマプリセット管理
```bash
# プリセット一覧
context-manage-themes list

# 新しいプリセット作成
context-manage-themes create my-theme

# プリセット適用
context-manage-themes apply my-theme
```

### 🔧 ツール設定最適化システム

#### 自動設定最適化
```bash
# プロジェクト検出・自動設定
context-configure-tools auto

# 特定プロファイル適用
context-configure-tools profile full_stack_web
context-configure-tools profile systems_engineer
context-configure-tools profile data_scientist
```

#### 設定状態確認
```bash
# 現在の設定状況
context-configure-tools status

# 設定リセット
context-configure-tools reset
```

#### 開発者プロファイル管理
```bash
# プロファイル一覧
context-manage-profiles list

# カスタムプロファイル作成
context-manage-profiles create my-profile

# プロファイル編集
context-manage-profiles edit my-profile

# プロファイル削除
context-manage-profiles delete my-profile
```

#### ツール使用分析
```bash
# 使用パターン分析
context-analyze-tools usage

# パフォーマンス分析
context-analyze-tools performance

# 最適化提案
context-analyze-tools recommendations
```

### ⚡ 電力・パフォーマンス管理システム

#### 電力状態・最適化
```bash
# 電力状態確認
context-manage-power status

# 自動最適化
context-manage-power auto

# 特定プロファイル適用
context-manage-power profile power_saver
context-manage-power profile balanced
context-manage-power profile performance
```

#### 継続監視
```bash
# リアルタイム監視
context-manage-power monitor
```

#### パフォーマンス最適化
```bash
# 自動ボトルネック検出
context-optimize-performance auto

# メモリ最適化
context-optimize-performance memory

# ディスク最適化
context-optimize-performance disk

# ネットワーク最適化
context-optimize-performance network
```

## 🔄 統合ワークフロー例

### 新プロジェクト開始時
```bash
# 1. プロジェクト検出
context-detect-project detect

# 2. 環境セットアップ
context-detect-environment detect

# 3. ツール設定自動調整
context-configure-tools auto

# 4. テーマ最適化
context-adapt-theme auto

# 5. 電力プロファイル設定
context-manage-power auto
```

### 日常作業開始時
```bash
# 場所学習（初回のみ）
context-learn-location office

# 全体状況確認・最適化
context-monitor-resources status
context-adapt-theme auto
context-manage-power auto
```

### パフォーマンス問題時
```bash
# リソース状況確認
context-monitor-resources status

# 問題分析
context-optimize-performance auto

# 電力プロファイル調整
context-manage-power auto
```

## 📊 設定カスタマイズ

### プロファイル別設定

#### Minimal設定
```nix
dotfiles.context = {
  enable = true;
  profile = "minimal";
  # プロジェクト検出、リソース監視、電力管理のみ
};
```

#### Standard設定（推奨）
```nix
dotfiles.context = {
  enable = true;
  profile = "standard";
  # 全機能有効、高度な機能は無効
};
```

#### Full設定
```nix
dotfiles.context = {
  enable = true;
  profile = "full";
  # 全機能有効、AI学習、クラウド連携含む
};
```

### 個別機能設定
```nix
dotfiles.context = {
  enable = true;
  profile = "standard";
  
  # 個別設定で上書き可能
  themeAdaptation.fatigueAdaptation.enable = false;
  powerManagement.cloudOffloading.enable = true;
  toolConfiguration.toolchainManagement.enable = true;
};
```

## 📁 データ保存場所

### 設定データ
```
~/.local/share/dotfiles-context/
├── projects/           # プロジェクト検出履歴
├── environment/        # 環境認識データ
├── resources/          # リソース監視ログ
├── themes/            # テーマ適用履歴
├── tools/             # ツール設定状態
├── power/             # 電力管理履歴
├── locations/         # 学習済み場所データ
└── profiles/          # カスタムプロファイル
```

### 設定ファイル
```
~/.config/nvim/lua/context/profile.lua     # Neovim設定
~/.config/Code/User/context-settings.json  # VS Code設定
~/.local/share/dotfiles-context/aliases-*.sh # シェルエイリアス
```

## 🔧 トラブルシューティング

### よくある問題

#### コマンドが認識されない
```bash
# 設定再構築
just rebuild

# 開発シェルで試行
nix develop
```

#### 権限エラー
```bash
# sudo権限が必要な場合（電力管理等）
# パスワード入力が必要な操作は手動実行
```

#### データが保存されない
```bash
# ディレクトリ確認
ls -la ~/.local/share/dotfiles-context/

# 権限確認
ls -ld ~/.local/share/dotfiles-context/
```

### デバッグ情報
```bash
# システム情報確認
context-detect-project status
context-detect-environment summary
context-monitor-resources status

# 設定確認
nix eval .#darwinConfigurations.macOS-arm.config.dotfiles.context.enable
```

## 📚 追加リソース

### ドキュメント
- [Phase 3 完成状況](/docs/PHASE3_COMPLETION_STATUS.md)
- [Phase 3 残作業計画](/docs/PHASE3_REMAINING_TASKS.md)
- [技術仕様書](/docs/TECHNICAL_SPECIFICATIONS.md)

### 設定例
- メイン設定: `/nix/common/context/default.nix`
- 個別モジュール: `/nix/common/context/detection/`

### 拡張・カスタマイズ
- カスタムプロファイル作成
- 新しい検出ルール追加
- 独自最適化ロジック実装