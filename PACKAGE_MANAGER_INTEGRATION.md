# 📦 パッケージマネージャー統合ガイド

**作成日**: 2025年6月17日  
**目的**: npm、pip等のパッケージマネージャーをnix/home-managerで統合管理

---

## ✅ 統合完了したパッケージマネージャー

### 1️⃣ Node.js エコシステム
```nix
# home.packages
nodejs_20    # Node.js LTS
yarn         # Alternative package manager  
pnpm         # Fast, disk space efficient

# programs.npm
npm.enable = true;  # npmrc管理可能
```

### 2️⃣ Python エコシステム  
```nix
# home.packages
python312                      # Python 3.12
python312Packages.pip          # pip
python312Packages.virtualenv   # 仮想環境
python312Packages.pipx         # アプリケーション分離インストール
```

---

## 🔧 統合設定の詳細

### 環境変数設定
```nix
home.sessionVariables = {
  # Node.js最適化
  NODE_OPTIONS = "--max-old-space-size=4096";
  NPM_CONFIG_PREFIX = "${homeDirectory}/.npm-global";
  
  # Python環境
  PYTHON_VENV_PATH = "${homeDirectory}/.local/share/virtualenvs";
};
```

### 便利なエイリアス
```bash
# npm shortcuts
ni = "npm install"
nr = "npm run"  
nt = "npm test"
nb = "npm run build"

# Python shortcuts  
py = "python3"
pip = "pip3"
venv = "python3 -m venv"
activate = "source ./venv/bin/activate"

# Alternative managers
yi = "yarn install"
pi = "pnpm install"
```

---

## 🎯 使用方法とベストプラクティス

### Node.js プロジェクト開発
```bash
# nix管理のNode.js使用
node --version  # v20.x.x (LTS)

# パッケージ管理
ni              # npm install (エイリアス)
nr dev          # npm run dev
nb              # npm run build

# 代替マネージャー
yi              # yarn install  
pi              # pnpm install
```

### Python プロジェクト開発
```bash
# nix管理のPython使用
py --version    # Python 3.12.x

# 仮想環境作成
venv myproject
activate        # source ./venv/bin/activate

# パッケージインストール
pip install django
```

---

## 📋 メリット・制限事項

### ✅ メリット
1. **一元管理**: パッケージマネージャー自体をnixで統一
2. **バージョン固定**: 決定論的な環境再現
3. **設定統合**: 環境変数・エイリアスの宣言的管理
4. **プロジェクト分離**: direnvとの組み合わせで完全分離

### ⚠️ 制限事項・注意点
1. **プロジェクト依存**: package.json, requirements.txtは従来通り
2. **グローバル vs ローカル**: グローバルインストールは控えめに
3. **キャッシュ管理**: npm/pip キャッシュは各自で管理必要

---

## 🔄 移行戦略

### Phase 1: 並行運用（推奨）
```bash
# 既存: nodebrew + システムpip
/Users/yuki/.nodebrew/current/bin/npm

# 新規: nix管理
/Users/yuki/.nix-profile/bin/npm
```

### Phase 2: 段階的移行
1. **新プロジェクト**: nix管理ツール使用
2. **既存プロジェクト**: そのまま継続（必要時移行）
3. **PATH優先度**: nix > nodebrew で設定

### Phase 3: 完全移行（オプション）
```bash
# nodebrew無効化（オプション）
# PATH優先度でnix管理ツールを優先使用
```

---

## 🛠️ 高度な統合オプション

### direnv統合（プロジェクト別環境）
```bash
# .envrc でプロジェクト固有設定
use nix
layout node  # Node.js環境
layout python  # Python環境
```

### nix-shell での開発環境
```nix
# shell.nix でプロジェクト専用環境
{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    nodejs_20
    python312
    # プロジェクト固有の依存関係
  ];
}
```

---

## 📊 実行結果

### 適用前
- Node.js: nodebrew管理
- Python: システム管理  
- pip: バージョン混在

### 適用後  
- ✅ 統一されたパッケージマネージャー管理
- ✅ 宣言的な環境変数設定
- ✅ 便利なエイリアス (20+ shortcuts)
- ✅ プロジェクト分離対応

---

## 🚀 次回適用方法

```bash
# home-manager設定適用
USER=yuki hms  # home-manager switch エイリアス

# 新しいツール確認
which node     # nix管理版
which npm      # nix管理版  
which python3  # nix管理版

# エイリアス確認
ni --help      # npm install
py --version   # python3
```

**結論**: パッケージマネージャーの完全nix統合により、宣言的で再現可能な開発環境が実現されます。