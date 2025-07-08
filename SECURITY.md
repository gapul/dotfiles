# セキュリティガイドライン

## 🔒 概要

このドキュメントでは、dotfilesシステムのセキュリティ実装と運用ガイドラインを説明します。


## 📋 暗号化戦略

### **SOPS統一暗号化戦略 (2025年6月19日更新)**

**Git-crypt廃止**: 全ての秘密情報をSOPSで統一管理

#### **SOPS統一管理対象**
| 機密情報の種類 | 管理場所 | 利点 |
|---------------|----------|------|
| **APIキー・認証トークン** | secrets.api.* | 構造化管理、Nix統合 |
| **SSH秘密鍵・証明書** | secrets.ssh.*、secrets.ssl.* | マルチライン暗号化 |
| **環境変数・設定値** | secrets.development.env_vars.* | 一元管理 |
| **設定ファイル全体** | secrets.development.* | ファイル内容暗号化 |

### **実装状況**
- ✅ **SOPS-nix**: Age暗号化、統一secrets-unified.yaml管理
- ❌ **Git-crypt**: 完全廃止 (2025年6月19日)
- ✅ **セキュリティベースライン**: SSH/Firewall/Audit設定
- ✅ **簡素化**: 1つのツール、1つの鍵、1つのファイルで全管理

## 🎯 クイックスタート

### **1. セキュリティシステム初期化**
```bash
# セキュリティモジュール有効化確認
nix eval .#darwinConfigurations.default.config.sops.secrets

# セットアップスクリプト実行
./nix/security/scripts/setup-security.sh
```

### **2. SOPS設定**
```bash
# Age鍵生成
age-keygen -o ~/.config/sops/age/keys.txt

# シークレット編集
sops nix/security/sops/secrets-darwin.yaml
```

### **3. 統一secrets設定**
```bash
# 統一secretsファイル作成
cp nix/security/sops/secrets-unified.yaml.example nix/security/sops/secrets-unified.yaml

# Age暗号化対象設定
export SOPS_AGE_RECIPIENTS="$(age-keygen -y ~/.config/sops/age/keys.txt)"

# ファイル暗号化
sops -e -i nix/security/sops/secrets-unified.yaml

# 暗号化済みファイル編集
sops nix/security/sops/secrets-unified.yaml
```

---

## 🔐 レガシー: 管理対象外ファイル（従来のセキュリティ方式）

**注意**: 以下は従来の手動管理方式です。
現在は上記のSOPS統一暗号化システムの使用を推奨します。


## 🔒 管理対象外ファイル（セキュリティ上の理由）

以下のファイルは個人情報やセンシティブな情報を含むため、**GitHubにアップロードしません**：

### 除外される設定ファイル
- **`.gitconfig`** - 実名、メールアドレス
- **`ssh/config`** - サーバー情報、IPアドレス、接続設定
- **`claude.json`** - ユーザーID、プロジェクト履歴、API設定

### 除外される認証ファイル
- **SSH秘密鍵** (`id_rsa`, `id_ed25519` など)
- **APIキー・トークン**
- **環境変数ファイル** (`.env`, `.env.local`)

## 📋 テンプレートファイルの使用

センシティブファイルの代わりに、`.example` ファイルを提供しています：

```bash
configs/git/.gitconfig.example       # Git設定のテンプレート
configs/ssh/config.example           # SSH設定のテンプレート  
configs/apps/claude/claude.json.example  # Claude設定のテンプレート
```

## 🛠️ セットアップ手順

1. **テンプレートファイルをコピー**
   ```bash
   cp configs/git/.gitconfig.example configs/git/.gitconfig
   cp configs/ssh/config.example configs/ssh/config
   cp configs/apps/claude/claude.json.example configs/apps/claude/claude.json
   ```

2. **個人情報を設定**
   ```bash
   # .gitconfig を編集
   vim configs/git/.gitconfig
   
   # 実名とメールアドレスを設定
   [user]
       name = Your Real Name
       email = your.email@example.com
   ```

3. **手動でシンボリックリンクを作成**
   ```bash
   ln -sf "$PWD/configs/git/.gitconfig" ~/.gitconfig
   ln -sf "$PWD/configs/ssh/config" ~/.ssh/config
   ln -sf "$PWD/configs/apps/claude/claude.json" ~/.claude.json
   ```

## ⚠️ 重要な注意事項

### やってはいけないこと
- ❌ 実際の設定ファイルをGitリポジトリに含める
- ❌ 秘密鍵や認証トークンをコミットする
- ❌ 個人のサーバー情報を公開する

### 推奨事項
- ✅ `.example` ファイルのみをコミットする
- ✅ 実際の設定ファイルは `.gitignore` で除外する
- ✅ ローカル環境でのみ実際の設定を管理する

## 🔍 セキュリティチェック

コミット前に以下をチェックしてください：

```bash
# センシティブファイルがステージされていないことを確認
git status

# .gitignore が正しく動作していることを確認
git check-ignore configs/git/.gitconfig
git check-ignore configs/ssh/config
git check-ignore configs/apps/claude/claude.json
```

すべて `configs/...` と表示されれば正常に除外されています。


## 🔐 SOPS による宣言的シークレット管理

### 概要

`sops-nix` を使用して、機密情報を安全に暗号化・管理できます。
これにより：
- 機密情報を暗号化してリポジトリに保存可能
- Nix設定から暗号化されたシークレットにアクセス
- 環境の完全な宣言的再現が可能

### セットアップ手順

1. **Age keyの生成**
   ```bash
   # Age暗号化キーを生成
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   
   # 公開キーを確認（次の手順で使用）
   grep "public key:" ~/.config/sops/age/keys.txt
   ```

2. **secrets.yamlファイルの作成**
   ```bash
   # テンプレートをコピー
   cp secrets.yaml.example secrets.yaml
   
   # 実際のシークレット値を設定
   vim secrets.yaml
   ```

3. **SOPSによる暗号化**
   ```bash
   # 公開キーを環境変数に設定（上記で確認した公開キー）
   export SOPS_AGE_RECIPIENTS="age1your_public_key_here"
   
   # ファイルを暗号化
   sops -e -i secrets.yaml
   ```

4. **Nix設定での利用**
   ```nix
   # darwin.nix での設定例
   sops.secrets."github_token" = {
     path = "/run/secrets/github_token";
     owner = config.users.users.yuki.name;
     group = "staff";
     mode = "0400";
   };
   ```

### ファイル編集

```bash
# 暗号化されたファイルの編集
sops secrets.yaml

# 特定のキーのみ編集
sops --set '["new_key"] "new_value"' secrets.yaml
```

### 利用可能なシークレット

`secrets.yaml.example` を参照して、以下のようなシークレットを管理できます：
- GitHub API tokens
- OpenAI/Claude API keys
- SSH private keys
- Database credentials
- Cloud service keys
- Application-specific secrets

### トラブルシューティング

**復号エラーが発生する場合：**
```bash
# キーファイルの権限確認
ls -la ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# SOPS_AGE_KEY_FILE環境変数の設定
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
```

**darwin-rebuild時のエラー：**

⚠️  **重要**: Age鍵ファイルに`chmod 644`を設定することは**重大なセキュリティリスク**です。


**推奨される解決策：**
```bash
# 1. 安全な権限でAge鍵を維持
chmod 600 ~/.config/sops/age/keys.txt

# 2. nix-darwinでSOPS-nixを正しく設定
# sops.age.keyFileオプションでNixデーモンがアクセス可能な場所を指定
sops.age.keyFile = "/var/lib/sops-nix/keys.txt";  # システムレベル
# または
sops.age.keyFile = "${config.users.users.yuki.home}/.config/sops/age/keys.txt";  # ユーザーレベル

# 3. システムレベルでの安全な鍵配置
sudo mkdir -p /var/lib/sops-nix
sudo cp ~/.config/sops/age/keys.txt /var/lib/sops-nix/keys.txt
sudo chmod 600 /var/lib/sops-nix/keys.txt
sudo chown root:wheel /var/lib/sops-nix/keys.txt
```

**なぜ`chmod 644`が危険なのか：**
- 秘密鍵が全ユーザーから読み取り可能になる
- システム上の任意のプロセスが暗号化キーにアクセス可能
- セキュリティモデルが完全に破綻する

## 📞 サポート

セキュリティに関する質問や問題を発見した場合は、パブリックなIssueではなく、直接連絡してください。
