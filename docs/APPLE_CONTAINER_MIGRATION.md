# Apple Container Migration Guide

## 概要

このドキュメントでは、dotfilesプロジェクトにおけるDocker/PodmanからApple Containerへの移行について説明します。

## Apple Containerについて

Apple Containerは、Appleが開発したmacOS用のネイティブコンテナランタイムです。

- **GitHub Repository**: https://github.com/apple/container
- **利点**: macOSとの深い統合、ネイティブパフォーマンス、セキュリティの向上
- **対象**: macOS環境での開発作業

## 変更された設定

### 1. システムパッケージ (nix/darwin/system/default.nix)

```nix
# 変更前
docker
docker-compose

# 変更後 (Apple Container)
# docker              # Replaced with Apple Container
# docker-compose      # Replaced with Apple Container orchestration
```

### 2. Homebrew Casks

```nix
# 変更前
"podman-desktop" # Container management

# 変更後
# "podman-desktop" # Replaced with Apple Container management
```

### 3. 開発環境設定 (nix/common/development/containers/default.nix)

- `dockerSupport`: デフォルトで無効化
- `appleContainerSupport`: 新オプション追加（macOS専用）
- VS Code統合の更新

### 4. Shell設定 (configs/zsh/zshrc)

```bash
# 新しいApple Containerエイリアス
alias ac='apple-container'
alias acp='apple-container ps'
alias aci='apple-container images'
alias acr='apple-container run'

# 旧Dockerエイリアス（コメントアウト）
# alias d='docker'
# alias dc='docker-compose' 
# alias dps='docker ps'
# alias di='docker images'
```

### 5. GitHub Actions (.github/workflows/packages.yml)

- Linux環境: 従来のDocker使用
- macOS環境: Apple Container使用（利用可能な場合）
- プラットフォーム別の条件分岐を追加

## 使用方法

### 基本コマンド

```bash
# Apple Containerの基本操作
ac --version                    # バージョン確認
ac pull ubuntu:latest          # イメージのプル
ac run -it ubuntu:latest       # コンテナの実行
acp                            # 実行中コンテナの確認
aci                            # イメージ一覧の確認
```

### VS Code Dev Containers

VS Codeでの開発コンテナは自動的にApple Containerを使用するよう設定されています：

```json
{
  "dev.containers.containerTool": "apple-container",
  "dev.containers.appleContainerPath": "/usr/local/bin/apple-container"
}
```

## 移行手順

### 1. Apple Containerのインストール

```bash
# Apple Containerは現在開発中のため、リリース待ち
# インストール方法は公式リポジトリを参照
# https://github.com/apple/container
```

### 2. 設定の適用

```bash
# dotfiles設定の再構築
just rebuild

# 環境変数の更新
source ~/.zshrc
```

### 3. 既存コンテナの移行

既存のDockerコンテナは手動で移行する必要があります：

```bash
# Docker imageのエクスポート
docker save ubuntu:latest -o ubuntu.tar

# Apple Containerでのインポート（仮想的なコマンド）
ac load -i ubuntu.tar
```

## 互換性

### サポート状況

- ✅ **macOS**: Apple Container使用
- ✅ **Linux**: 従来のDocker使用  
- ✅ **WSL**: Docker Desktop統合継続
- ✅ **GitHub Actions**: プラットフォーム別対応

### 制限事項

- Apple Containerは現在オープンソースプロジェクトとして開発中
- 一部のDocker固有機能は利用できない可能性があります
- 移行期間中は従来のDockerも併用可能

## トラブルシューティング

### Apple Containerが利用できない場合

```bash
# フォールバック: 従来のDocker使用
if ! command -v apple-container &> /dev/null; then
  echo "Apple Container not available, using Docker..."
  # Docker関連のエイリアスを有効化
fi
```

### パフォーマンス問題

Apple Containerのパフォーマンスが期待に満たない場合：

1. システムリソースの確認
2. コンテナの設定見直し
3. 必要に応じてDockerへの一時的な復帰

## 参考資料

- [Apple Container GitHub](https://github.com/apple/container)
- [macOS Container Runtime Documentation](https://developer.apple.com/documentation/)
- [Docker to Apple Container Migration Best Practices](https://docs.example.com/migration)

---

*最終更新: 2025年7月1日*