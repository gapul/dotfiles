# セキュリティガイドライン

このドットファイル管理システムはセキュリティを重視して設計されています。

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

`sops-nix` を使用して、機密情報を安全に暗号化・管理できます。これにより：
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
```bash
# nix-darwin側でキーが見つからない場合
sudo chmod 644 ~/.config/sops/age/keys.txt
# 注意: 適切なファイル権限を設定してください
```

## 📞 サポート

セキュリティに関する質問や問題を発見した場合は、パブリックなIssueではなく、直接連絡してください。