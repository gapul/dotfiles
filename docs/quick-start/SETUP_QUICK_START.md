# 5分間クイックセットアップ

> ⚡ **最速でdotfilesを動作させるための必須手順のみ**

## 🚀 必須コマンド (5分以内)

### 1. 基本セットアップ
```bash
# Nixインストール (未インストールの場合)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# リポジトリクローン・移動
git clone https://github.com/username/dotfiles ~/.dotfiles
cd ~/.dotfiles

# 初期ビルド
nix develop
```

### 2. プラットフォーム設定
```bash
# macOS
just darwin-rebuild

# Linux  
just home-rebuild

# WSL
just wsl-rebuild
```

### 3. 即座確認
```bash
# 設定適用確認
which nix && echo "✅ Nix正常"
direnv version && echo "✅ direnv正常"
starship --version && echo "✅ starship正常"
```

## 🔧 問題解決

| 問題 | 解決方法 |
|------|----------|
| Nixコマンドが見つからない | `source ~/.nix-profile/etc/profile.d/nix.sh` |
| 権限エラー | `sudo chown -R $USER ~/.nix-store` |
| ビルドエラー | `nix flake check` で設定検証 |

## 📚 次のステップ

- **詳細セットアップ**: [guides/SETUP_GUIDE.md](../guides/SETUP_GUIDE.md)
- **開発環境**: [guides/DEVELOPMENT_ENVIRONMENT_GUIDE.md](../guides/DEVELOPMENT_ENVIRONMENT_GUIDE.md)
- **カスタマイズ**: [guides/comprehensive/](../guides/comprehensive/)

*セットアップ所要時間: 約5分*
