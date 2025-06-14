# ドットファイル管理対象 - 発見結果

このドキュメントは、システム全体を探索して発見したドットファイルと設定ファイルをまとめています。

## 🎯 推奨管理対象ファイル（高優先度）

### シェル・ターミナル関連
```bash
~/.zshrc                    # Zsh設定（メイン）
~/.zprofile                 # Zshプロファイル
~/.bash_history            # Bashコマンド履歴（※バックアップのみ）
~/.zsh_history             # Zshコマンド履歴（※バックアップのみ）
```

### Git・バージョン管理
```bash
~/.gitconfig               # Git設定
```

### SSH・セキュリティ
```bash
~/.ssh/config              # SSH接続設定
# 注意: 秘密鍵（id_rsa, id_ed25519等）は管理対象外
```

### 開発ツール設定
```bash
~/.config/starship.toml    # Starshipプロンプト設定
~/.docker/config.json      # Docker設定
~/.claude.json            # Claude設定
~/.condarc               # Conda設定
```

## 🔧 環境固有管理対象（中優先度）

### ウィンドウマネージャー・デスクトップ環境
```bash
~/.config/yabai/yabairc     # Yabaiタイル型ウィンドウマネージャー
~/.config/skhd/skhdrc       # skhdキーバインド設定
~/.config/sketchybar/       # Sketchybarステータスバー設定
├── init.lua
├── colors.lua
├── settings.lua
├── sketchybarrc
├── icons.lua
├── bar.lua
└── default.lua
```

### エディター・IDE設定
```bash
# VSCode設定（クロスプラットフォーム）
~/Library/Application Support/Code/User/settings.json

# Zed設定
~/.config/zed/settings.json

# Cursor設定（探索結果では設定ファイル未発見）
```

## 📱 アプリケーション設定（任意・低優先度）

### 開発関連アプリ
```bash
# Claude Desktop
~/Library/Application Support/Claude/config.json
~/Library/Application Support/Claude/claude_desktop_config.json

# Docker関連
~/.docker/daemon.json
~/.docker/.token_seed（※セキュリティ上管理対象外）

# その他開発ツール
~/.local/share/CMakeTools/cmake-tools-kits.json
```

### コミュニケーション・ツール
```bash
# Discord
~/Library/Application Support/discord/settings.json

# その他チャットアプリ設定
~/Library/Application Support/Beeper/electron-config.json
~/Library/Application Support/Element/electron-config.json
```

## ⚠️ 管理対象外ファイル（セキュリティ・一時ファイル）

### 秘密鍵・認証情報
```bash
~/.ssh/id_rsa              # SSH秘密鍵
~/.ssh/id_ed25519          # SSH秘密鍵
~/.vault-token             # Vault認証トークン
~/.docker/.token_seed      # Docker認証トークン
```

### システム・一時ファイル
```bash
~/.DS_Store               # macOSシステムファイル
~/.CFUserTextEncoding     # macOSエンコーディング設定
~/.lesshst               # lessコマンド履歴
~/.viminfo               # Vimセッション情報
~/.zshrc.swp/.swo/.swn   # Vimスワップファイル
```

### キャッシュ・ログディレクトリ
```bash
~/.cache/                 # 各種キャッシュ
~/.thumbnails/           # サムネイルキャッシュ
~/.zsh_sessions/         # Zshセッション
```

## 📂 管理方法の推奨ディレクトリ構造

```
dotfiles/configs/
├── shell/
│   ├── .zshrc
│   └── .zprofile
├── git/
│   └── .gitconfig
├── ssh/
│   └── config
├── terminal/
│   └── starship.toml
├── wm/                   # Window Manager
│   ├── yabai/
│   │   └── yabairc
│   ├── skhd/
│   │   └── skhdrc
│   └── sketchybar/
│       ├── init.lua
│       ├── colors.lua
│       └── ...
├── editors/
│   ├── vscode/
│   │   └── settings.json
│   └── zed/
│       └── settings.json
├── development/
│   ├── docker/
│   │   └── config.json
│   ├── .claude.json
│   └── .condarc
└── apps/                 # Optional
    ├── discord/
    └── claude/
```

## 🚀 実装計画

### Phase 1: 基本設定（必須）
1. シェル設定（.zshrc, .zprofile）
2. Git設定（.gitconfig）
3. SSH設定（config）
4. 基本開発ツール（starship.toml, .claude.json, .condarc）

### Phase 2: 開発環境（推奨）
1. Docker設定
2. VSCode/Zed設定
3. ターミナル環境設定

### Phase 3: デスクトップ環境（任意）
1. Yabai + skhd設定
2. Sketchybar設定
3. その他UI関連設定

### Phase 4: アプリケーション設定（任意）
1. 各種アプリ設定
2. 環境固有設定

## 📝 設定ファイルサイズ・重要度

| ファイル | サイズ | 重要度 | 移植性 |
|---------|--------|--------|--------|
| .zshrc | 中 | 高 | 高 |
| .gitconfig | 小 | 高 | 高 |
| starship.toml | 大 | 中 | 高 |
| SSH config | 小 | 高 | 中 |
| yabai/skhd | 中 | 中 | 低（macOS限定） |
| VSCode settings | 中 | 中 | 高 |

## 🔧 次のステップ

1. **install.sh更新**: 発見したファイルを管理対象に追加
2. **ディレクトリ構造作成**: 推奨構造に基づいてconfigsディレクトリを整理
3. **既存ファイルコピー**: 現在の設定を適切な場所にコピー
4. **段階的導入**: Phase 1から順次実装