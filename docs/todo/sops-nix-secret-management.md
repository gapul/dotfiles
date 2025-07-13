# sops-nixシークレット管理の完全実装 - TODO

**ID**: todo-3  
**優先度**: 高  
**推定時間**: 3-4時間  
**ステータス**: 準備完了（実装待ち）

## 概要

現在dotfilesにはsops-nixの基盤が整備されているが、実際のシークレット暗号化管理が未実装。Git設定やSSH設定を安全に管理するための完全実装が必要。

## 実装目標

- **宣言的シークレット管理**: Nixでシークレットを安全に管理
- **Git設定暗号化**: ユーザー情報とトークンの暗号化
- **SSH設定暗号化**: SSH鍵と設定の安全な管理
- **age暗号化**: 強力な暗号化によるセキュリティ確保

## 実装手順

### 1. age鍵ペア生成とセットアップ

```bash
# age CLIインストール（必要に応じて）
nix profile install nixpkgs#age

# 鍵ペア生成
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# 公開鍵を確認（.sops.yamlで使用）
grep "# public key:" ~/.config/sops/age/keys.txt
```

### 2. .sops.yaml設定ファイル作成

```yaml
# .sops.yaml
creation_rules:
  - path_regex: nix/secrets/.*\.yaml$
    age: age1xyz... # 上記で生成した公開鍵
    encrypted_regex: ^(data|stringData|password|token|key|secret)$
```

### 3. シークレットファイル作成

#### nix/secrets/user-secrets.yaml
```yaml
# nix/secrets/user-secrets.yaml (暗号化前)
git:
  username: "gapul"
  email: "yuk8337@gmail.com"
  github_token: "ghp_your_actual_token_here"

ssh:
  github_host: "github.com"
  github_user: "git"
```

#### 暗号化実行
```bash
# ファイルを暗号化
sops --encrypt --in-place nix/secrets/user-secrets.yaml

# 暗号化確認
cat nix/secrets/user-secrets.yaml  # 暗号化されたコンテンツが表示される
```

### 4. Nix設定での暗号化ファイル利用

#### nix/common/security/sops.nix作成
```nix
{ config, lib, pkgs, ... }:

{
  # sops-nixモジュール有効化
  sops = {
    age.keyFile = "/Users/yuki/.config/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/user-secrets.yaml;
    
    secrets = {
      # Git設定
      "git-username" = {
        path = "${config.xdg.configHome}/git/username";
        mode = "0400";
      };
      "git-email" = {
        path = "${config.xdg.configHome}/git/email";
        mode = "0400";
      };
      "github-token" = {
        path = "${config.xdg.configHome}/github/token";
        mode = "0400";
      };
      
      # SSH設定
      "ssh-config" = {
        path = "/Users/yuki/.ssh/config";
        mode = "0600";
      };
    };
  };
}
```

#### Git設定でのシークレット利用
```nix
# nix/common/development/git.nix更新
{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    lfs.enable = true;
    
    # シークレットファイルから設定を読み込み
    userName = lib.mkDefault (lib.fileContents "${config.xdg.configHome}/git/username");
    userEmail = lib.mkDefault (lib.fileContents "${config.xdg.configHome}/git/email");
    
    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = false;
      core.editor = "nvim";
      
      # GitHub CLI認証でトークン使用
      credential."https://github.com" = {
        helper = "store --file=${config.xdg.configHome}/github/token";
      };
    };
  };
}
```

### 5. SSH設定の暗号化管理

#### nix/secrets/ssh-config.yaml作成
```yaml
# nix/secrets/ssh-config.yaml (暗号化前)
ssh_config: |
  Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_rsa
    IdentitiesOnly yes
    
  Host *.compute.amazonaws.com
    User ubuntu
    IdentityFile ~/.ssh/aws-key.pem
```

### 6. 自動復号化とリンク設定

#### nix/common/security/default.nix
```nix
{ config, lib, pkgs, ... }:

{
  imports = [
    ./sops.nix
  ];
  
  # シークレットファイルの自動復号化とシンボリックリンク
  home.activation = {
    setupSecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Git設定の復号化確認
      if [ -f "${config.xdg.configHome}/git/username" ]; then
        echo "✅ Git secrets successfully decrypted"
      else
        echo "❌ Git secrets not found - check sops configuration"
      fi
      
      # SSH設定の復号化確認
      if [ -f "/Users/yuki/.ssh/config" ]; then
        echo "✅ SSH config successfully decrypted"
      else
        echo "❌ SSH config not found - check sops configuration"
      fi
    '';
  };
}
```

### 7. ヘルスチェック機能実装

#### scripts/security-health-check.sh
```bash
#!/usr/bin/env bash
# セキュリティ設定ヘルスチェック

echo "🔒 Security Configuration Health Check"
echo "======================================"

# age鍵ファイル確認
if [ -f ~/.config/sops/age/keys.txt ]; then
    echo "✅ Age private key: Found"
else
    echo "❌ Age private key: Missing"
fi

# .sops.yaml確認
if [ -f .sops.yaml ]; then
    echo "✅ SOPS config: Found"
else
    echo "❌ SOPS config: Missing"
fi

# 暗号化ファイル確認
if [ -f nix/secrets/user-secrets.yaml ]; then
    echo "✅ Encrypted secrets: Found"
    
    # 復号化テスト
    if sops --decrypt nix/secrets/user-secrets.yaml > /dev/null 2>&1; then
        echo "✅ Decryption test: Passed"
    else
        echo "❌ Decryption test: Failed"
    fi
else
    echo "❌ Encrypted secrets: Missing"
fi

# Git設定復号化確認
if [ -f ~/.config/git/username ]; then
    echo "✅ Git secrets: Decrypted"
else
    echo "❌ Git secrets: Not decrypted"
fi

# SSH設定確認
if [ -f ~/.ssh/config ]; then
    echo "✅ SSH config: Available"
    # 権限確認
    perms=$(ls -l ~/.ssh/config | awk '{print $1}')
    if [[ $perms == "-rw-------"* ]]; then
        echo "✅ SSH permissions: Secure (600)"
    else
        echo "⚠️  SSH permissions: $perms (should be 600)"
    fi
else
    echo "❌ SSH config: Missing"
fi
```

## 完了条件

- [ ] age鍵ペアが生成され、安全に保存されている
- [ ] .sops.yamlが正しく設定されている
- [ ] Git設定（ユーザー名、メール、トークン）が暗号化されている
- [ ] SSH設定が暗号化管理されている
- [ ] Nixビルド時に自動的にシークレットが復号化される
- [ ] セキュリティヘルスチェックが全て緑になる
- [ ] Git操作が正常に動作する（認証含む）
- [ ] SSH接続が正常に動作する

## セキュリティ考慮事項

### 暗号化対象
- Git設定のユーザー情報とトークン
- SSH設定と鍵ファイル
- API キーやアクセストークン
- その他の機密情報

### 除外対象
- 公開しても問題ない設定項目
- デフォルトのシェル設定
- 一般的なアプリケーション設定

### バックアップ戦略
- age秘密鍵の安全なバックアップ
- 暗号化ファイルのバージョン管理
- 復旧手順の文書化

## トラブルシューティング

### よくある問題
1. **age鍵ファイルが見つからない**
   - 鍵ファイルのパス確認
   - 権限設定の確認

2. **復号化に失敗する**
   - .sops.yaml設定の確認
   - 公開鍵の一致確認

3. **Nixビルドでエラー**
   - sops-nixモジュールのインポート確認
   - 暗号化ファイルのパス確認

## 関連ファイル

- `.sops.yaml` - 暗号化ルール設定
- `nix/secrets/` - 暗号化ファイル格納ディレクトリ
- `nix/common/security/` - セキュリティ関連Nix設定
- `~/.config/sops/age/keys.txt` - age秘密鍵
- `scripts/security-health-check.sh` - ヘルスチェックスクリプト

## 参考資料

- [sops-nix公式ドキュメント](https://github.com/Mic92/sops-nix)
- [age暗号化ツール](https://github.com/FiloSottile/age)
- [SOPS公式ガイド](https://github.com/mozilla/sops)

---

**作成日**: 2025年7月13日  
**最終更新**: 2025年7月13日  
**作成者**: Claude Code Assistant