# Slidev Environment Troubleshooting Guide

**問題解決とトラブルシューティングの包括的ガイド**

## 📋 目次

- [環境構築の問題](#環境構築の問題)
- [Slidev固有の問題](#slidev固有の問題)
- [パフォーマンスの問題](#パフォーマンスの問題)
- [出力・エクスポートの問題](#出力エクスポートの問題)
- [Nix環境の問題](#nix環境の問題)
- [一般的なエラーメッセージ](#一般的なエラーメッセージ)

## 環境構築の問題

### 🔴 `direnv: error: .envrc is blocked` エラー

**症状**: direnvが`.envrc`を読み込まない

**解決策**:
```bash
# direnvを許可
direnv allow

# 設定確認
cat .envrc  # "use flake" が記載されているか確認

# direnv再読み込み
direnv reload
```

**根本原因**: セキュリティのためdirenvはデフォルトで`.envrc`をブロック

---

### 🔴 `nix: command not found` エラー

**症状**: Nixがインストールされていない、またはパスが通っていない

**解決策**:
```bash
# Nixインストール状況確認
which nix

# Nixインストール（未インストールの場合）
curl -L https://nixos.org/nix/install | sh

# シェル再起動
exec $SHELL

# Nix環境の読み込み
source ~/.nix-profile/etc/profile.d/nix.sh
```

---

### 🔴 `error: experimental feature 'flakes' is not enabled`

**症状**: Nix Flakesが有効化されていない

**解決策**:
```bash
# Nix設定ディレクトリ作成
mkdir -p ~/.config/nix

# Flakes有効化
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# または一時的に有効化
nix --experimental-features "nix-command flakes" develop
```

---

### 🔴 Node.js/npm関連エラー

**症状**: `npm ERR!` または `node: command not found`

**解決策**:
```bash
# Nix環境確認
nix develop

# Node.js確認
node --version  # v22.16.0 が表示されるはず
npm --version   # 10.9.2 が表示されるはず

# 環境変数確認
echo $PATH | grep nix

# 手動でNode.js環境構築
nix shell nixpkgs#nodejs_22 nixpkgs#npm
```

## Slidev固有の問題

### 🔴 `@slidev/cli not found` エラー

**症状**: Slidev CLIが見つからない

**解決策**:
```bash
# プロジェクトディレクトリで実行
cd your-presentation/

# Slidev CLI手動インストール
npm install @slidev/cli

# グローバルインストール（非推奨）
npm install -g @slidev/cli

# Nix環境での実行確認
npx slidev --version
```

---

### 🔴 テーマが見つからないエラー

**症状**: `theme "seriph" was not found`

**解決策**:
```bash
# テーマを明示的にインストール
npm install @slidev/theme-seriph

# 利用可能なテーマ確認
npm search @slidev/theme

# package.jsonに追加
cat >> package.json << 'EOF'
{
  "dependencies": {
    "@slidev/theme-seriph": "latest"
  }
}
EOF

# 再インストール
npm install
```

---

### 🔴 `dev server failed to start` エラー

**症状**: 開発サーバーが起動しない

**解決策**:
```bash
# ポート使用状況確認
lsof -i :3030

# 別ポートで起動
npm run dev -- --port 3031

# キャッシュクリア
rm -rf node_modules/.cache
rm -rf .slidev

# 完全なリセット
rm -rf node_modules package-lock.json
npm install
```

---

### 🔴 スライドが表示されない

**症状**: ブラウザで空白ページが表示される

**解決策**:
```bash
# ブラウザコンソール確認（F12）
# JavaScriptエラーをチェック

# slides.mdの構文確認
head -20 slides.md  # フロントマターの確認

# 最小構成でテスト
cat > slides.md << 'EOF'
---
theme: default
---

# Test Slide

Hello World
EOF

# キャッシュ無効化でリロード
# Ctrl+Shift+R (Chrome/Firefox)
```

## パフォーマンスの問題

### 🔴 開発サーバーが重い

**症状**: ページ読み込みが遅い、レスポンスが悪い

**解決策**:
```bash
# メモリ使用量確認
ps aux | grep node

# 画像最適化
find . -name "*.jpg" -exec mogrify -resize 1920x1080\> {} \;
find . -name "*.png" -exec optipng {} \;

# 不要なファイル除外
echo "node_modules/
.cache/
dist/
*.log" >> .gitignore

# 開発モードでの最適化
npm run dev -- --optimize-deps
```

---

### 🔴 ビルドが失敗する

**症状**: `npm run build` でエラー

**解決策**:
```bash
# 詳細ログ有効化
npm run build -- --debug

# 依存関係確認
npm audit
npm audit fix

# TypeScript エラー確認
npx tsc --noEmit

# メモリ制限増加
node --max-old-space-size=4096 node_modules/.bin/slidev build
```

## 出力・エクスポートの問題

### 🔴 PDF出力でPlaywrightエラー

**症状**: `Error: Playwright not found`

**解決策**:
```bash
# Playwright Chromiumインストール
npm install -D playwright-chromium

# ブラウザバイナリインストール
npx playwright install chromium

# 手動でPuppeteer使用
npm install -D puppeteer
export PUPPETEER_EXECUTABLE_PATH=$(which chromium)
```

---

### 🔴 PDFレイアウトが崩れる

**症状**: PDF出力でスライドが正しく表示されない

**解決策**:
```bash
# CSS print media 対応
echo "@media print {
  .slidev-layout { page-break-after: always; }
}" >> styles/print.css

# 高解像度出力
npx slidev export --with-clicks --width 1920 --height 1080

# 代替ブラウザ使用
PLAYWRIGHT_BROWSER=webkit npx slidev export
```

---

### 🔴 画像が表示されない（PDF）

**症状**: PDF出力で画像が欠ける

**解決策**:
```bash
# 相対パス確認
# ❌ ../images/logo.png
# ✅ /images/logo.png または ./public/images/logo.png

# 画像ファイル権限確認
chmod 644 public/images/*

# Base64エンコード（小さい画像）
base64 public/images/logo.png
# data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...
```

## Nix環境の問題

### 🔴 `building '/nix/store/...' failed`

**症状**: Nixビルドが失敗する

**解決策**:
```bash
# Nixキャッシュクリア
nix-collect-garbage -d

# フレーク更新
nix flake update

# 強制再構築
nix develop --rebuild

# エラー詳細確認
nix develop --show-trace
```

---

### 🔴 パッケージが見つからない

**症状**: `error: attribute 'package-name' missing`

**解決策**:
```bash
# パッケージ検索
nix search nixpkgs package-name

# 利用可能なパッケージ確認
nix flake show nixpkgs

# 代替パッケージ確認
nix search nixpkgs ".*editor.*"

# flake.nixの依存関係確認
cat flake.nix | grep -A 20 "buildInputs"
```

---

### 🔴 macOS権限エラー

**症状**: `operation not permitted` エラー

**解決策**:
```bash
# Xcode Command Line Tools確認
xcode-select --install

# ディスク権限確認
ls -la /nix

# Nixデーモン再起動
sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist
sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist

# 手動権限修正
sudo chown -R $(whoami) /nix/var/nix/profiles/per-user/$(whoami)
```

## 一般的なエラーメッセージ

### `EADDRINUSE: address already in use`

**原因**: ポート3030が既に使用中

**解決**: 
```bash
# プロセス確認・終了
lsof -ti:3030 | xargs kill -9

# 別ポート使用
npm run dev -- --port 3031
```

---

### `Cannot resolve module './components/...'`

**原因**: Vueコンポーネントパスエラー

**解決**:
```bash
# パス確認
ls -la components/

# 相対パス修正
# ❌ import MyComp from './components/MyComp'
# ✅ import MyComp from '~/components/MyComp'
```

---

### `TypeError: Cannot read property of undefined`

**原因**: JavaScript/TypeScriptランタイムエラー

**解決**:
```bash
# ブラウザ開発者ツール確認
# F12 > Console

# TypeScript型チェック
npx tsc --noEmit

# Vueコンポーネント構文確認
npx vue-tsc --noEmit
```

---

### `Module not found: Can't resolve 'fs'`

**原因**: Node.js モジュールのブラウザ実行

**解決**:
```javascript
// vite.config.ts
export default defineConfig({
  define: {
    global: 'globalThis',
  },
  resolve: {
    alias: {
      fs: false,
      path: false,
    }
  }
})
```

## デバッグ手法

### 詳細ログの有効化

```bash
# Slidev詳細ログ
DEBUG=slidev* npm run dev

# Vite詳細ログ  
DEBUG=vite* npm run dev

# 全体デバッグ
DEBUG=* npm run dev 2>&1 | grep -E "(error|Error|ERROR)"
```

### 環境診断スクリプト

```bash
#!/bin/bash
# diagnose.sh - 環境診断スクリプト

echo "=== Slidev Environment Diagnosis ==="

echo "1. System Information:"
uname -a
echo "Node.js: $(node --version 2>/dev/null || echo 'Not found')"
echo "npm: $(npm --version 2>/dev/null || echo 'Not found')"
echo "Nix: $(nix --version 2>/dev/null || echo 'Not found')"
echo "direnv: $(direnv --version 2>/dev/null || echo 'Not found')"

echo -e "\n2. Nix Environment:"
echo "NIX_PATH: $NIX_PATH"
echo "Flake check: $(nix flake check 2>&1 | head -1)"

echo -e "\n3. Project Status:"
echo "Current directory: $(pwd)"
echo ".envrc exists: $(test -f .envrc && echo 'Yes' || echo 'No')"
echo "slides.md exists: $(test -f slides.md && echo 'Yes' || echo 'No')"
echo "package.json exists: $(test -f package.json && echo 'Yes' || echo 'No')"

echo -e "\n4. Port Availability:"
echo "Port 3030: $(lsof -ti:3030 >/dev/null && echo 'In use' || echo 'Available')"

echo -e "\n5. Slidev Status:"
echo "CLI available: $(npx slidev --version 2>/dev/null || echo 'Not found')"

echo -e "\n=== End of Diagnosis ==="
```

### 段階的な問題切り分け

1. **最小構成テスト**
   ```bash
   # 新規プロジェクトで動作確認
   nix run .#new -- test-debug
   cd test-debug
   npm run dev
   ```

2. **依存関係の確認**
   ```bash
   # パッケージ整合性チェック
   npm ls
   npm audit
   ```

3. **設定ファイルの検証**
   ```bash
   # 設定ファイル構文チェック
   node -e "console.log(JSON.parse(require('fs').readFileSync('package.json')))"
   ```

## サポート・ヘルプ

### 公式リソース

- [Slidev Issues](https://github.com/slidevjs/slidev/issues)
- [Slidev Discussions](https://github.com/slidevjs/slidev/discussions)
- [Nix Discourse](https://discourse.nixos.org/)

### ログ収集

問題報告時に有用な情報:

```bash
# 環境情報収集
{
  echo "System: $(uname -a)"
  echo "Node: $(node --version)"
  echo "npm: $(npm --version)"
  echo "Nix: $(nix --version)"
  echo "Slidev: $(npx slidev --version)"
  echo "Error log:"
  npm run dev 2>&1 | tail -50
} > debug-info.txt
```

---

## 🔗 関連ドキュメント

- [USER_GUIDE.md](USER_GUIDE.md) - 基本的な使用方法
- [BEST_PRACTICES.md](BEST_PRACTICES.md) - 推奨方法と回避策
- [メインREADME](../README.md) - プロジェクト概要

---

*🤖 Generated with [Claude Code](https://claude.ai/code)*