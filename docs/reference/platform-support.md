# プラットフォーム対応リファレンス

dotfilesシステムのマルチプラットフォーム対応詳細です。

## 🎯 対応プラットフォーム

### macOS（Darwin）
| 種類 | アーキテクチャ | 管理システム | 状態 |
|------|----------------|--------------|------|
| Apple Silicon | aarch64 | nix-darwin + Homebrew | ✅ 完全対応 |
| Intel | x86_64 | nix-darwin + Homebrew | ✅ 完全対応 |

**特徴：**
- システム設定の宣言的管理
- Homebrewとの統合
- GUI アプリケーション対応
- ネイティブパフォーマンス最適化

### Linux
| ディストリビューション | 管理システム | 状態 |
|----------------------|--------------|------|
| NixOS | Nix + home-manager | ✅ 完全対応 |
| Ubuntu/Debian | home-manager | ✅ 完全対応 |
| Fedora/RHEL | home-manager | ✅ 完全対応 |
| Arch Linux | home-manager | ✅ 完全対応 |

**特徴：**
- ユーザー環境の宣言的管理
- GUI アプリケーション対応
- systemd サービス統合

### WSL（Windows Subsystem for Linux）
| 版 | ベースOS | 状態 |
|----|----------|------|
| WSL2 | Ubuntu 22.04+ | ✅ 完全対応 |
| WSL2 | Other distros | 🔄 部分対応 |

**特徴：**
- Windows統合機能
- 限定的なGUI対応
- 開発環境特化

### Android（Termux）
| 環境 | アーキテクチャ | 状態 |
|------|----------------|------|
| Termux | aarch64 | ✅ 基本対応 |
| nix-on-droid | aarch64 | 🔄 実験的 |

**特徴：**
- リソース制約対応
- 軽量パッケージ構成
- CLI ツール中心

## 🏗️ アーキテクチャ設計

### プラットフォーム検出システム
```nix
# 自動検出ロジック
platform = 
  if isDarwin then
    if isAarch64 then "darwin-aarch64" else "darwin-x86_64"
  else if isLinux then
    if pathExists "/etc/nixos" then "nixos"
    else if match ".*Microsoft.*" versionContent then "wsl"
    else if match ".*android.*" versionContent then "android"
    else "linux"
  else "unknown";
```

### 機能マトリックス
| 機能 | macOS | Linux | WSL | Android |
|------|-------|-------|-----|---------|
| GUI アプリ | ✅ | ✅ | 🔄 | ❌ |
| システム設定 | ✅ | 🔄 | ❌ | ❌ |
| 開発環境フル | ✅ | ✅ | ✅ | 🔄 |
| コンテナ実行 | ✅ | ✅ | ✅ | ❌ |
| VPN対応 | ✅ | ✅ | ✅ | ❌ |

**凡例：**
- ✅ 完全対応
- 🔄 部分対応・制約あり  
- ❌ 非対応

## 📦 プラットフォーム別パッケージ

### 共通パッケージ（全プラットフォーム）
```nix
corePackages = [
  # 基本CLIツール
  git curl wget jq vim htop
  
  # ファイル操作
  file unzip gzip bzip2 xz
  
  # テキスト処理
  gnugrep gnused gawk
];
```

### プラットフォーム固有パッケージ

#### macOS専用
```nix
darwinPackages = [
  mas                 # Mac App Store CLI
  coreutils-prefixed  # GNU coreutils (g-prefix)
  dockutil           # Dock管理
];
```

#### Linux専用  
```nix
linuxPackages = [
  systemd            # システム管理
  xclip             # クリップボード
  desktop-file-utils # デスクトップ統合
];
```

#### WSL専用
```nix
wslPackages = [
  wslu              # WSL utilities
  win32yank         # Windows clipboard
];
```

#### Android専用
```nix
androidPackages = [
  busybox           # 軽量ユーティリティ
  termux-api        # Termux API access
];
```

## ⚙️ 設定管理戦略

### 階層化設定
```
1. 共通設定（nix/common/）
   ↓
2. プラットフォーム設定（nix/{darwin,linux,wsl,android}/）
   ↓
3. ユーザー固有設定（環境変数・オーバーライド）
```

### 条件分岐パターン
```nix
# 機能ベース分岐
lib.optionals (capabilities.hasGUI) guiPackages

# プラットフォーム直接分岐  
if isDarwin then darwinSpecific else linuxSpecific

# リソース制約分岐
lib.optionals (!capabilities.limitedResources) heavyPackages
```

## 🔧 移植・対応拡張

### 新プラットフォーム追加手順

1. **検出ロジック追加**
   ```nix
   # nix/common/platform-detection.nix
   else if newPlatformCondition then "new-platform"
   ```

2. **プラットフォーム設定作成**
   ```bash
   mkdir nix/new-platform
   echo '{ ... }: { }' > nix/new-platform/default.nix
   ```

3. **flake.nix統合**
   ```nix
   newPlatformConfiguration = ...;
   ```

4. **CI/CD対応**
   ```yaml
   # .github/workflows/platform-test.yml
   strategy:
     matrix:
       platform: [..., new-platform]
   ```

### 制約事項と回避策

#### Android制約
- **問題**: メモリ・ストレージ制限
- **対策**: 軽量パッケージ選択、遅延ロード

#### WSL制約  
- **問題**: systemd非対応（古いWSL）
- **対策**: 機能検出による条件分岐

#### ネットワーク制約
- **問題**: 企業プロキシ環境
- **対策**: プロキシ設定自動検出・適用

## 📊 パフォーマンス最適化

### プラットフォーム別最適化
```nix
optimizations = {
  # ジョブ並列度
  maxJobs = 
    if capabilities.limitedResources then 1
    else if isDarwin && isAarch64 then 8  # Apple Silicon
    else 4;
    
  # メモリ使用量
  maxMemoryMB =
    if capabilities.limitedResources then 1024
    else if isDarwin && isAarch64 then 8192
    else 4096;
    
  # ビルド設定
  enableParallelBuilding = !capabilities.limitedResources;
  useCompression = capabilities.limitedResources;
};
```

### キャッシュ戦略
- **High-end**: 積極的キャッシュ利用
- **Low-end**: 選択的キャッシュ、圧縮重視
- **Mobile**: ネットワーク使用量制限

## 🧪 テスト・検証

### プラットフォーム別テスト
```bash
# 統合テストスクリプト
just test-platform darwin
just test-platform linux  
just test-platform wsl
just test-platform android
```

### CI/CDマトリックス
```yaml
strategy:
  matrix:
    platform:
      - macos-latest     # Darwin
      - ubuntu-latest    # Linux
      - windows-latest   # WSL
    include:
      - platform: android
        container: android-nix
```

---

*最終更新: 2025年7月2日*