# Slidev Best Practices Guide

**効果的なプレゼンテーション作成のためのベストプラクティス集**

## 📋 目次

- [プレゼンテーション設計](#プレゼンテーション設計)
- [コンテンツ作成](#コンテンツ作成)
- [コード品質](#コード品質)
- [パフォーマンス最適化](#パフォーマンス最適化)
- [チーム開発](#チーム開発)
- [セキュリティ](#セキュリティ)

## プレゼンテーション設計

### 🎯 目的とターゲット設定

```markdown
---
# 📝 プレゼンテーション設計チェックリスト
title: "明確で具体的なタイトル"
info: |
  ## 目的
  - このプレゼンテーションで達成したいこと
  - ターゲットオーディエンス
  - 期待される成果

  ## 構成
  1. 導入 (5分)
  2. 主要コンテンツ (20分) 
  3. まとめ・質疑応答 (5分)
---
```

### 📏 スライド構成の原則

**推奨構成**:
1. **タイトルスライド** - 第一印象を決める
2. **アジェンダ** - 全体の流れを示す
3. **導入** - 背景・問題提起
4. **本論** - 核心となる内容
5. **まとめ** - 要点の再確認
6. **質疑応答** - インタラクション

**スライド数の目安**:
- 5分発表: 5-8スライド
- 15分発表: 15-20スライド  
- 30分発表: 25-35スライド

```markdown
# ✅ 良い例: 簡潔で焦点が明確

# AI活用による開発効率向上

## 今日お話しすること
- 現状の課題分析
- AI導入戦略  
- 実際の成果指標

---

# ❌ 悪い例: 情報過多

# AIを活用した次世代開発環境における生産性向上とチーム協調の最適化、および持続可能な組織運営モデルの構築に向けた包括的アプローチ

## 今日お話しすること（詳細版）
- 現状分析（技術的課題、組織課題、リソース制約、外部要因）
- AI導入戦略（ツール選定、段階的導入、ROI測定、リスク管理）
- ...（続く）
```

## コンテンツ作成

### 📝 効果的なMarkdown記述

#### 1. フロントマターの最適化

```markdown
---
# テーマ選択: 用途に応じて適切に
theme: seriph          # 技術系・ダーク
# theme: apple-basic   # シンプル・ミニマル
# theme: academic      # 学術・フォーマル

# 背景: 適切なサイズと品質
background: https://source.unsplash.com/1920x1080/?technology
# または
# background: ./public/images/background.jpg

# 基本設定
title: "明確なタイトル"
class: text-center
highlighter: shiki     # コードハイライト
lineNumbers: true      # 行番号表示
drawings:
  enabled: true        # 描画機能
  persist: false       # 描画の永続化

# アニメーション設定
transition: slide-left  # スライド切り替え
css: unocss           # CSS フレームワーク
---
```

#### 2. コンテンツ階層の明確化

```markdown
# ✅ 良い例: 明確な階層

# メインタイトル

## セクション見出し

### サブセクション

- 重要なポイント
- **強調したい内容**
- `技術用語`

---

# ❌ 悪い例: 階層が不明確

## タイトル
### 重要な話
- いろいろ
#### でも、これも大事
- あと、これ
##### 細かい話
```

#### 3. 視覚的要素の効果的活用

```markdown
# データの可視化

<div grid="~ cols-2 gap-4">
<div>

## 従来の方法
- 手動デプロイ
- 設定ドリフト  
- 長時間のセットアップ

</div>
<div>

## Nix Flakes
- 宣言的設定
- 完全な再現性
- 1コマンドセットアップ

</div>
</div>

<v-click>

### 結果: **90%** の時間短縮

</v-click>
```

### 🎨 デザイン原則

#### カラーパレットの統一

```css
/* カスタムCSS */
:root {
  --primary: #3b82f6;      /* ブルー */
  --secondary: #8b5cf6;    /* パープル */
  --accent: #10b981;       /* グリーン */
  --warning: #f59e0b;      /* オレンジ */
  --error: #ef4444;        /* レッド */
}

.highlight {
  background: var(--primary);
  color: white;
  padding: 0.25rem 0.5rem;
  border-radius: 0.25rem;
}
```

#### 読みやすいタイポグラフィ

```markdown
# タイトル: 24-32pt
## セクション: 20-24pt  
### サブセクション: 16-20pt
本文: 14-16pt
注釈: 12-14pt

**太字**: 重要な概念
*斜体*: 用語・定義
`コード`: 技術用語
```

## コード品質

### 💻 コードブロックのベストプラクティス

#### 1. 言語指定と適切な例

```markdown
# ✅ 良い例: 実用的なコード

```typescript
// 型安全なAPI呼び出し
interface ApiResponse<T> {
  data: T;
  status: number;
  message: string;
}

async function fetchUser(id: string): Promise<ApiResponse<User>> {
  const response = await fetch(`/api/users/${id}`);
  return response.json();
}
```

# ❌ 悪い例: 不完全・非現実的

```javascript
// なんかAPIを呼ぶ
function getData() {
  // TODO: 実装する
  return {};
}
```
```

#### 2. 段階的なコード説明

```markdown
# APIの実装

<v-clicks>

```typescript
// 1. 基本的なインターフェース定義
interface User {
  id: string;
  name: string;
  email: string;
}
```

```typescript  
// 2. API レスポンス型
interface ApiResponse<T> {
  data: T;
  status: number;
}
```

```typescript
// 3. 完全な実装
async function createUser(userData: Omit<User, 'id'>): Promise<ApiResponse<User>> {
  const user = { id: generateId(), ...userData };
  await saveToDatabase(user);
  return { data: user, status: 201 };
}
```

</v-clicks>
```

### 🔧 Vue.jsコンポーネントの活用

#### インタラクティブなデモ

```vue
<template>
  <div class="demo-container">
    <h3>{{ title }}</h3>
    <div class="metrics">
      <div v-for="metric in metrics" :key="metric.name" class="metric">
        <span class="label">{{ metric.name }}</span>
        <span class="value" :class="metric.trend">{{ metric.value }}</span>
      </div>
    </div>
    <button @click="updateMetrics" class="refresh-btn">
      🔄 Update
    </button>
  </div>
</template>

<script setup>
import { ref } from 'vue'

const title = ref('System Metrics')
const metrics = ref([
  { name: 'CPU Usage', value: '45%', trend: 'good' },
  { name: 'Memory', value: '2.1GB', trend: 'warning' },
  { name: 'Disk I/O', value: '15MB/s', trend: 'good' }
])

function updateMetrics() {
  // リアルタイムデータ更新のシミュレーション
  metrics.value = metrics.value.map(m => ({
    ...m,
    value: Math.random() > 0.5 ? `${Math.floor(Math.random() * 100)}%` : m.value
  }))
}
</script>

<style scoped>
.demo-container { padding: 1rem; border: 1px solid #e5e7eb; border-radius: 0.5rem; }
.metrics { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1rem; margin: 1rem 0; }
.metric { text-align: center; }
.good { color: #10b981; }
.warning { color: #f59e0b; }
</style>
```

## パフォーマンス最適化

### 🚀 読み込み速度の改善

#### 1. 画像最適化

```bash
# 画像の自動最適化スクリプト
#!/bin/bash
# optimize-images.sh

for file in public/images/*.{jpg,jpeg,png}; do
  if [[ -f "$file" ]]; then
    # JPEG: 品質85%で圧縮
    if [[ "$file" =~ \.(jpg|jpeg)$ ]]; then
      magick "$file" -quality 85 -resize 1920x1080\> "$file"
    fi
    
    # PNG: OptiPNGで最適化
    if [[ "$file" =~ \.png$ ]]; then
      optipng -o5 "$file"
    fi
  fi
done
```

#### 2. 遅延読み込みの実装

```markdown
# 重い画像の遅延読み込み

<v-click>
  <img 
    src="/images/large-diagram.png" 
    alt="System Architecture"
    loading="lazy"
    style="max-width: 100%; height: auto;"
  />
</v-click>

# 段階的な情報公開
<v-clicks>

- 📊 **データ収集**: ログ・メトリクス
- 🔍 **分析**: パターン認識
- 📈 **可視化**: ダッシュボード
- ⚡ **自動化**: アラート・対応

</v-clicks>
```

#### 3. リソース最適化

```typescript
// vite.config.ts - ビルド最適化
import { defineConfig } from 'vite'

export default defineConfig({
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['vue', '@vueuse/core'],
          slidev: ['@slidev/client']
        }
      }
    }
  },
  optimizeDeps: {
    include: ['@slidev/client', 'vue']
  }
})
```

### 📱 レスポンシブデザイン

```css
/* レスポンシブスタイル */
.slide-content {
  padding: 2rem;
}

/* タブレット */
@media (max-width: 768px) {
  .slide-content {
    padding: 1rem;
    font-size: 0.9rem;
  }
  
  .grid-cols-2 {
    grid-template-columns: 1fr;
  }
}

/* モバイル */
@media (max-width: 480px) {
  .slide-content {
    padding: 0.5rem;
    font-size: 0.8rem;
  }
}
```

## チーム開発

### 👥 コラボレーション

#### 1. プロジェクト構造の標準化

```
presentation-project/
├── slides.md              # メインコンテンツ
├── components/             # 再利用可能コンポーネント
│   ├── Chart.vue          # データ可視化
│   ├── CodeBlock.vue      # カスタムコードブロック
│   └── Timeline.vue       # タイムライン表示
├── layouts/                # カスタムレイアウト
│   ├── intro.vue          # 導入スライド用
│   └── comparison.vue     # 比較表示用
├── public/
│   ├── images/            # 画像リソース
│   ├── videos/            # 動画ファイル
│   └── data/              # JSONデータ
├── styles/
│   ├── global.css         # グローバルスタイル
│   └── components.css     # コンポーネント用
├── package.json
└── README.md              # プロジェクト説明
```

#### 2. コミット規約

```bash
# コミットメッセージの規約
feat: Add interactive demo component
fix: Resolve image loading issue  
docs: Update installation guide
style: Improve slide typography
refactor: Reorganize component structure
test: Add unit tests for Chart component
```

#### 3. 共有コンポーネントライブラリ

```vue
<!-- components/shared/MetricCard.vue -->
<template>
  <div class="metric-card" :class="variant">
    <div class="metric-value">{{ value }}</div>
    <div class="metric-label">{{ label }}</div>
    <div class="metric-change" :class="changeType">
      {{ change }}
    </div>
  </div>
</template>

<script setup>
interface Props {
  label: string
  value: string | number
  change?: string
  variant?: 'primary' | 'secondary' | 'success' | 'warning'
  changeType?: 'positive' | 'negative' | 'neutral'
}

const props = withDefaults(defineProps<Props>(), {
  variant: 'primary',
  changeType: 'neutral'
})
</script>
```

### 📋 レビュープロセス

#### コンテンツレビューチェックリスト

```markdown
## プレゼンテーションレビューシート

### ✅ 構成・内容
- [ ] 目的とターゲットが明確
- [ ] 論理的な流れ
- [ ] 重要ポイントの強調
- [ ] 時間配分の適切性

### ✅ 技術・デザイン  
- [ ] テーマの統一性
- [ ] 読みやすいフォント・色
- [ ] 画像・図表の品質
- [ ] アニメーションの適切性

### ✅ 動作確認
- [ ] 全スライドの表示確認
- [ ] インタラクティブ要素の動作
- [ ] PDF出力の品質
- [ ] 異なる環境での動作

### ✅ アクセシビリティ
- [ ] 色覚に配慮した色選択
- [ ] 十分なコントラスト比
- [ ] スクリーンリーダー対応
- [ ] キーボードナビゲーション
```

## セキュリティ

### 🔒 機密情報の管理

#### 1. 環境変数の活用

```typescript
// 機密情報は環境変数で管理
const API_KEY = import.meta.env.VITE_API_KEY
const DATABASE_URL = import.meta.env.VITE_DATABASE_URL

// ❌ 悪い例: ハードコード
const API_KEY = "sk-1234567890abcdef"
```

#### 2. .gitignoreの適切な設定

```bash
# .gitignore
node_modules/
dist/
.env
.env.local
.env.*.local

# 機密ファイル
*.key
*.pem
secret-*.json

# OS固有
.DS_Store
Thumbs.db

# エディタ
.vscode/
.idea/
*.swp
*.swo
```

#### 3. 公開時の注意点

```markdown
# 公開前チェックリスト

## 🔍 機密情報確認
- [ ] APIキー・パスワードの除去
- [ ] 社内URL・IPアドレスの匿名化
- [ ] 個人情報の削除・匿名化
- [ ] 社外秘情報の確認

## 📤 公開設定
- [ ] 適切な公開範囲設定
- [ ] アクセス権限の確認
- [ ] バックアップの取得
- [ ] ライセンス情報の明記
```

### 🛡️ 依存関係のセキュリティ

```bash
# 定期的なセキュリティ監査
npm audit
npm audit fix

# 特定の脆弱性確認
npm audit --audit-level high

# 依存関係の更新
npm update
nix flake update
```

## 実践的なテンプレート

### 🎯 技術系プレゼンテーション

```markdown
---
theme: seriph
background: https://source.unsplash.com/1920x1080/?code,technology
title: "技術導入提案: XXXシステム"
info: |
  ## 技術導入提案
  - 現状課題の分析
  - 解決策の提示  
  - 実装計画と効果測定
class: text-center
highlighter: shiki
lineNumbers: true
---

# XXXシステム導入提案

**効率性とスケーラビリティの実現**

<div class="pt-12">
  <span @click="$slidev.nav.next" class="px-2 py-1 rounded cursor-pointer">
    Press Space to start →
  </span>
</div>

---

# 現状の課題

<v-clicks>

- 🐌 **パフォーマンス**: 処理時間が長い
- 🔧 **保守性**: 複雑な依存関係
- 📈 **スケーラビリティ**: 負荷増加への対応困難
- 🔒 **セキュリティ**: 脆弱性の存在

</v-clicks>

<v-click>

## 📊 数値で見る現状

| 項目 | 現在 | 目標 |
|------|------|------|
| 応答時間 | 3.2秒 | <1秒 |
| 可用性 | 95% | 99.9% |
| デプロイ時間 | 2時間 | 5分 |

</v-click>
```

### 📊 ビジネス系プレゼンテーション

```markdown
---
theme: apple-basic
background: https://source.unsplash.com/1920x1080/?business,graph
title: "Q4 業績レポート"
class: text-center
---

# Q4 業績レポート

**持続的成長への取り組み**

---
layout: center
---

# 主要な成果

<div grid="~ cols-3 gap-8">
<div class="text-center">

## 📈 売上
**+25%**
前年同期比

</div>
<div class="text-center">

## 👥 チーム
**+15人**
新規採用

</div>
<div class="text-center">  

## 🎯 目標達成
**110%**
計画対比

</div>
</div>
```

---

## 🎓 まとめ

効果的なSlidevプレゼンテーション作成のための重要ポイント:

1. **明確な目的設定**と適切な構成
2. **視覚的に魅力的**なデザイン
3. **技術的品質**の確保
4. **チーム協力**とレビュープロセス
5. **セキュリティ**への配慮

これらのベストプラクティスを活用して、印象的で効果的なプレゼンテーションを作成しましょう。

---

## 🔗 関連リソース

- [USER_GUIDE.md](USER_GUIDE.md) - 詳細な使用方法
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - 問題解決
- [Slidev公式ドキュメント](https://sli.dev/)

---

*🤖 Generated with [Claude Code](https://claude.ai/code)*