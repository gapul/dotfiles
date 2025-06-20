# レガシー: 暗号化戦略ガイド

**重要なお知らせ**: このドキュメントは廃止予定です。

**Git-cryptは2025年6月19日に完全廃止され、SOPS-nix統一暗号化システムに置き換えられました。**

新しいセキュリティガイドは `SECURITY.md` を参照してください。

---

# 旧暗号化戦略ガイド: SOPS vs Git-crypt (廃止済み)

## 📋 概要

このドキュメントでは、dotfilesシステムにおける **SOPS** と **Git-crypt** の旧役割分担と使い分けガイドラインを説明します。

## 🔒 暗号化ツール比較

### **SOPS (Secrets OPerationS)**
```yaml
# 構造化データの暗号化に特化
api_key: ENC[AES256_GCM,data:xxx,tag:yyy]
database:
  password: ENC[AES256_GCM,data:zzz,tag:aaa]
```

### **Git-crypt**
```bash
# ファイル単位の透明暗号化
*.key filter=git-crypt diff=git-crypt
secrets/** filter=git-crypt diff=git-crypt
```

## 🎯 役割分担の原則

### **SOPS を使用する場合**

#### ✅ **推奨用途**
1. **構造化された機密データ**
   - API キー、トークン
   - データベース認証情報  
   - サービス固有の設定値
   - 環境変数セット

2. **Nix/NixOS統合が必要な機密情報**
   - システム設定に埋め込む秘密情報
   - Home-manager設定で参照する認証情報
   - CI/CD環境での自動展開が必要な値

3. **プラットフォーム固有の機密設定**
   ```yaml
   # secrets-darwin.yaml (macOS専用)
   macos:
     keychain_password: "secret_value"
   
   # secrets-linux.yaml (Linux専用)  
   linux:
     sudo_password: "secret_value"
   ```

#### 🔧 **SOPS の技術的利点**
- **部分暗号化**: ファイル構造は見える、値のみ暗号化
- **Diff-friendly**: 変更箇所が特定しやすい
- **多重暗号化**: Age + GPG の併用サポート
- **プラットフォーム統合**: Nix/Kubernetes/Terraform ネイティブサポート

### **Git-crypt を使用する場合**

#### ✅ **推奨用途**
1. **ファイル単位の機密保護**
   - SSH秘密鍵 (id_rsa, id_ed25519)
   - SSL/TLS証明書 (*.pem, *.crt)  
   - GPG鍵ファイル
   - バイナリ形式の認証情報

2. **設定ファイル全体の保護**
   - `.ssh/config` (接続先情報含む)
   - `.npmrc` (レジストリ認証情報)
   - `.docker/config.json` (Docker Hub認証)
   - プライベート環境設定ファイル

3. **透明な暗号化が必要な場合**
   ```bash
   # 暗号化されているが、通常のgit操作で透明に扱える
   git add secrets/private.key
   git commit -m "Add private key"  # 自動で暗号化される
   ```

#### 🔧 **Git-crypt の技術的利点**
- **透明暗号化**: 開発者は暗号化を意識せずに操作可能
- **ファイル単位**: 個別ファイルの完全保護
- **Git統合**: 通常のGitワークフローで自動暗号化/復号化
- **チーム協業**: GPG鍵による権限管理

## 📊 実装状況の分析

### **現在の設定構造**

```
nix/security/
├── sops/                          # SOPS管理エリア
│   ├── config/default.nix        # SOPS-nix設定
│   ├── secrets.yaml.example      # 共通シークレットテンプレート
│   └── secrets-darwin.yaml.example # macOS固有テンプレート
├── git-crypt/
│   └── config.nix                 # Git-crypt統合設定
└── baseline/
    └── security-baseline.nix      # セキュリティベースライン
```

### **暗号化対象の分類**

| 機密情報の種類 | SOPS | Git-crypt | 推奨理由 |
|---------------|------|-----------|----------|
| **APIキー・トークン** | ✅ | ❌ | 構造化データ、Nix統合 |
| **SSH秘密鍵** | ❌ | ✅ | バイナリファイル、透明暗号化 |
| **環境変数セット** | ✅ | ❌ | YAML構造、部分暗号化 |
| **設定ファイル全体** | ❌ | ✅ | ファイル単位保護 |
| **SSL証明書** | ❌ | ✅ | バイナリファイル |
| **データベース認証** | ✅ | ❌ | 構造化、システム統合 |

## 🎯 推奨戦略

### **A. デュアル暗号化戦略 (現在の実装)**

```yaml
# SOPS管理 (secrets-darwin.yaml)
github:
  token: "ENC[...]"  # API認証情報
api:
  openai_key: "ENC[...]"  # サービスキー
  anthropic_key: "ENC[...]"
database:
  postgresql_password: "ENC[...]"  # システム統合情報
```

```bash
# Git-crypt管理 (.gitattributes)
*.key filter=git-crypt              # SSH秘密鍵
*.pem filter=git-crypt              # SSL証明書  
.ssh/config filter=git-crypt        # SSH設定ファイル
.npmrc filter=git-crypt             # パッケージ管理認証
```

#### **利点**
- **最適化された保護**: 各データ種別に最適な暗号化手法
- **柔軟性**: 要件に応じた暗号化手法選択
- **統合性**: Nix ecosystem完全統合

#### **欠点**  
- **複雑性**: 2つのツールの学習・管理コスト
- **鍵管理**: Age + GPG の両方の鍵管理が必要

### **B. SOPS一本化戦略 (代替案)**

```yaml
# すべてをSOPSで管理
secrets:
  files:
    ssh_private_key: |
      ENC[AES256_GCM,data:-----BEGIN OPENSSH PRIVATE KEY-----
      ...,tag:xxx]
    ssl_certificate: |
      ENC[AES256_GCM,data:-----BEGIN CERTIFICATE-----
      ...,tag:yyy]
  config:
    github_token: "ENC[...]"
    database_password: "ENC[...]"
```

#### **利点**
- **一元管理**: 単一ツールでの統一管理
- **Nix統合**: 完全なNixOS/home-manager統合
- **鍵管理**: Age鍵のみの管理

#### **欠点**
- **YAML複雑化**: 大きなバイナリファイルの管理困難
- **Diff問題**: バイナリ変更時の差分確認困難

## 🎯 実装済み: SOPS統一戦略

### **Phase 1: SOPS一本化完了 (2025年6月19日実装)**

Git-cryptを廃止し、SOPS統一暗号化戦略を採用：

```yaml
# SOPS統一管理 (secrets-unified.yaml):
api:
  github_token: "ENC[...]"     # API認証情報
  openai_key: "ENC[...]"       # サービスキー
ssh:
  private_key: |               # SSH秘密鍵 (マルチライン)
    ENC[AES256_GCM,data:-----BEGIN OPENSSH PRIVATE KEY-----...]
ssl:
  certificate: |               # SSL証明書 (マルチライン)
    ENC[AES256_GCM,data:-----BEGIN CERTIFICATE-----...]
development:
  npmrc: |                     # 設定ファイル全体
    ENC[AES256_GCM,data://registry.npmjs.org/:_authToken=...]
```

**Git-crypt完全廃止**: 全ての秘密情報がSOPS管理に統一されました。

### **運用ガイドライン**

#### **新しい機密情報の分類フロー**

```mermaid
graph TD
    A[新しい機密情報] --> B{データ形式は？}
    B -->|構造化データ| C[SOPS使用]
    B -->|ファイル全体| D{用途は？}
    D -->|Nix設定統合| C
    D -->|透明暗号化| E[Git-crypt使用]
```

#### **チーム管理プロセス**

1. **SOPS鍵配布**
   ```bash
   # Age鍵生成・配布
   age-keygen -o ~/.config/sops/age/keys.txt
   sops updatekeys secrets-darwin.yaml
   ```

2. **Git-crypt権限管理**
   ```bash
   # GPG鍵での権限管理
   git-crypt add-gpg-user USER_GPG_KEY_ID
   git-crypt lock && git-crypt unlock
   ```

## 📚 操作リファレンス

### **SOPS操作**

```bash
# シークレット編集
sops nix/security/sops/secrets-darwin.yaml

# 新しいプラットフォーム用作成
cp secrets.yaml.example secrets-linux.yaml
sops -e -i secrets-linux.yaml

# 鍵ローテーション
sops updatekeys secrets-darwin.yaml
```

### **Git-crypt操作**

```bash
# 暗号化状況確認
git-crypt status

# ロック・アンロック
git-crypt lock
git-crypt unlock

# 新しいユーザー追加
git-crypt add-gpg-user GPG_KEY_ID
```

## 🔧 セキュリティベストプラクティス

### **共通原則**
1. **最小権限の原則**: 必要最小限の権限のみ付与
2. **定期的な鍵ローテーション**: 90日ごとの鍵更新
3. **アクセス監査**: 定期的な権限レビュー
4. **バックアップ**: 暗号化鍵の安全なバックアップ

### **SOPS固有**
- **Age + GPG併用**: 冗長性のための複数暗号化
- **プラットフォーム分離**: 環境別secrets file
- **部分暗号化**: 必要な値のみ暗号化

### **Git-crypt固有**  
- **GPG鍵管理**: 適切なGPG鍵の生成・管理
- **透明性**: チームメンバーへの操作教育
- **バックアップ**: 暗号化されたファイルのバックアップ

## 🎯 結論

**現在のデュアル暗号化戦略を推奨**します。

### **理由**
1. **最適化**: 各データ種別に最適な暗号化手法
2. **Nix統合**: SOPS-nixによる完全なシステム統合
3. **透明性**: Git-cryptによる開発体験向上
4. **実績**: 既に安定稼働している実装

### **管理コスト軽減策**
- **明確なガイドライン**: このドキュメントによる使い分け明確化
- **自動化**: セットアップスクリプトによる初期設定自動化
- **ドキュメント**: 操作手順の標準化

**この戦略により、セキュリティと利便性を両立した持続可能な暗号化システムを実現できます。**

---

**作成日**: 2025年6月19日  
**バージョン**: 1.0  
**対象システム**: Phase 4 セキュリティ管理システム