# Nix設定リファレンス

dotfilesシステムのNix設定の詳細リファレンスです。

## 📁 設定構造

### flake.nix（メインエントリーポイント）
```nix
{
  description = "Cross-platform dotfiles with Nix";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    home-manager.url = "github:nix-community/home-manager";
    sops-nix.url = "github:Mic92/sops-nix";
  };
}
```

### プラットフォーム検出

#### 対応プラットフォーム
- `darwin-aarch64`: Apple Silicon Mac
- `darwin-x86_64`: Intel Mac
- `nixos`: NixOS
- `linux`: 汎用Linux
- `wsl`: Windows Subsystem for Linux
- `android`: Termux/nix-on-droid

#### 機能検出
```nix
capabilities = {
  hasGUI = platform != "android" && platform != "wsl";
  supportsFullDevEnvironment = platform != "android";
  limitedResources = platform == "android";
  canRunContainers = platform != "android";
};
```

## 🎯 モジュール構成

### 共通モジュール (`nix/common/`)

#### `platform-detection.nix`
- プラットフォーム自動検出
- 機能・リソース制約の判定
- パッケージフィルタリング

#### `packages/core.nix`
- 基本CLIツール
- 開発言語ランタイム
- プラットフォーム固有パッケージ

#### `themes/colors.nix`
- 統一カラーパレット
- アプリケーション間テーマ連携

### プラットフォーム別モジュール

#### macOS (`nix/darwin/`)
```nix
# nix-darwin設定
system.defaults = {
  dock.autohide = true;
  finder.AppleShowAllExtensions = true;
};

homebrew = {
  enable = true;
  casks = [ "docker" "wezterm" ];
};
```

#### Linux (`nix/linux/`)
```nix
# home-manager設定
home.packages = with pkgs; [
  firefox
  vscode
];

services.gpg-agent.enable = true;
```

## 🔒 セキュリティ設定

### SOPS暗号化
```yaml
# .sops.yaml
keys:
  - &age_key age1crkk4dtd824qu3h5q24vnm4pmrjymzkelt60qnyzwcje74gncudqjr693n

creation_rules:
  - path_regex: secrets.*\.yaml$
    key_groups:
    - age:
      - *age_key
```

### 暗号化されたシークレット
```nix
sops.secrets = {
  github_token = {
    path = "/run/secrets/github_token";
    mode = "0400";
  };
};
```

## 📦 パッケージ管理

### カテゴリ別パッケージ
```nix
{
  coreTools = [
    git curl jq vim htop
  ];
  
  modernTools = lib.optionals (!limitedResources) [
    eza bat fd ripgrep fzf
  ];
  
  devTools = lib.optionals supportsFullDevEnvironment [
    nodejs python3 go rust
  ];
}
```

### プラットフォーム固有パッケージ
```nix
platformSpecific = 
  if isDarwin then [
    mas              # Mac App Store CLI
    coreutils-prefixed
  ] else if platform == "android" then [
    busybox          # 軽量ユーティリティ
  ] else [
    systemd
  ];
```

## ⚙️ 設定オプション

### 基本設定
```nix
{
  dotfiles = {
    profile = "standard";  # minimal, standard, full
    enableGUI = true;
    enableDevelopment = true;
  };
}
```

### プラットフォーム最適化
```nix
optimizations = {
  maxJobs = 
    if limitedResources then 1
    else if isDarwin && isAarch64 then 8
    else 4;
    
  enableParallelBuilding = !limitedResources;
  useCompression = limitedResources;
};
```

## 🔧 カスタマイズ

### 新しいパッケージの追加
```nix
# nix/common/packages/custom.nix
{ lib, pkgs, platformInfo, ... }:

{
  packages = with pkgs; lib.optionals (platformInfo.capabilities.supportsGUI) [
    your-gui-app
  ] ++ [
    your-cli-tool
  ];
}
```

### 新しいプラットフォームの追加
1. `nix/platforms/your-platform/` ディレクトリ作成
2. `default.nix` で設定定義
3. `platform-detection.nix` で検出ロジック追加
4. `flake.nix` でエントリーポイント登録

## 🐛 トラブルシューティング

### よくある問題

#### `error: selector 'darwinConfigurations' does not exist`
```bash
# flake.nixの場所を確認
nix flake show
# プロジェクトルートから実行していることを確認
```

#### `home-manager: option 'programs.git' defined multiple times`
```bash
# 重複モジュールをチェック
nix eval .#homeConfigurations.$USER.config.programs --json
```

#### `error: cannot evaluate attribute 'system'`
```bash
# プラットフォーム検出を確認
nix eval .#platformInfo --json
```

### デバッグコマンド
```bash
# 設定検証
nix flake check

# プラットフォーム情報確認
nix eval .#platformInfo --json

# パッケージ一覧
nix eval .#packages.$(nix eval --raw .#platformInfo.platform) --json
```

---

*最終更新: 2025年7月2日*