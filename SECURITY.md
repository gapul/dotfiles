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

## 📞 サポート

セキュリティに関する質問や問題を発見した場合は、パブリックなIssueではなく、直接連絡してください。