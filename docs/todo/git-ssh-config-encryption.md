# Git・SSH設定の暗号化管理実装 - TODO

**ID**: todo-4  
**優先度**: 中  
**推定時間**: 2-3時間  
**ステータス**: sops-nix基盤完了後に実装

## 概要

現在Git・SSH設定が平文で管理されており、セキュリティリスクが存在する。sops-nixを活用した暗号化管理への移行が必要。

## 現在の問題

### 平文管理されている設定
```bash
# Git設定の分散状況
~/.gitconfig         # ユーザー情報とLFS設定のみ
~/.config/git/config # メイン設定（Nixで生成済み）

# SSH設定
~/.ssh/config        # GitHub接続設定（平文）
~/.ssh/id_*          # SSH鍵ファイル（保護必要）
```

### セキュリティリスク
- ユーザー情報（メールアドレス）の暴露
- GitHub tokenの平文保存
- SSH設定の完全な可視性
- バックアップ時の機密情報漏洩

## 実装目標

- **統一設定管理**: Git設定の単一ソース化
- **シークレット暗号化**: 機密情報のsops-nix管理
- **SSH鍵の安全管理**: SSH鍵の暗号化とアクセス制御
- **設定テンプレート**: 再利用可能な設定構造

## 実装手順

### Phase 1: Git設定の統合と暗号化

#### 1. 現在の設定を確認・バックアップ
```bash
# 現在のGit設定確認
git config --list --show-origin

# 設定のバックアップ
cp ~/.gitconfig ~/.gitconfig.backup
cp ~/.config/git/config ~/.config/git/config.backup
```

#### 2. シークレット情報を暗号化ファイルに移動
```yaml
# nix/secrets/git-secrets.yaml（暗号化前）
git:
  user:
    name: "gapul"
    email: "yuk8337@gmail.com"
  github:
    username: "gapul"
    token: "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  signing:
    key: "your-gpg-key-id"
```

#### 3. Git設定のNix管理統一
```nix
# nix/common/development/git-secure.nix
{ config, lib, pkgs, ... }:

{
  # Git設定の暗号化ファイル読み込み
  sops.secrets = {
    "git-user-name" = {
      sopsFile = ../../secrets/git-secrets.yaml;
      path = "${config.xdg.configHome}/git/user-name";
      mode = "0400";
    };
    "git-user-email" = {
      sopsFile = ../../secrets/git-secrets.yaml;
      path = "${config.xdg.configHome}/git/user-email";
      mode = "0400";
    };
    "github-token" = {
      sopsFile = ../../secrets/git-secrets.yaml;
      path = "${config.xdg.configHome}/git/github-token";
      mode = "0400";
    };
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    
    # 暗号化されたファイルから設定を読み込み
    userName = lib.fileContents "${config.xdg.configHome}/git/user-name";
    userEmail = lib.fileContents "${config.xdg.configHome}/git/user-email";
    
    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = false;
      core.editor = "nvim";
      
      # GitHubトークン認証
      url."https://oauth2:$(cat ${config.xdg.configHome}/git/github-token)@github.com".insteadOf = "https://github.com";
      
      # GPG署名設定（オプション）
      commit.gpgsign = true;
      gpg.program = "${pkgs.gnupg}/bin/gpg";
    };
    
    # Git aliasesは平文のまま管理
    aliases = {
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
      visual = "!gitk";
    };
  };
  
  # 既存の.gitconfigを削除（重複回避）
  home.file.".gitconfig".enable = false;
}
```

### Phase 2: SSH設定の暗号化管理

#### 1. SSH設定情報の暗号化
```yaml
# nix/secrets/ssh-secrets.yaml（暗号化前）
ssh:
  github:
    hostname: "github.com"
    user: "git"
    identity_file: "~/.ssh/id_ed25519"
    identities_only: true
  
  aws:
    hostname: "*.compute.amazonaws.com"
    user: "ubuntu"
    identity_file: "~/.ssh/aws-key.pem"
    
  # SSH鍵の内容（Base64エンコード済み）
  keys:
    ed25519_private: "LS0tLS1CRUdJTi..." # 実際の秘密鍵内容
    ed25519_public: "ssh-ed25519 AAAAC3..." # 公開鍵内容
```

#### 2. SSH設定のNix管理
```nix
# nix/common/security/ssh-secure.nix
{ config, lib, pkgs, ... }:

{
  # SSH設定の暗号化管理
  sops.secrets = {
    "ssh-config" = {
      sopsFile = ../../secrets/ssh-secrets.yaml;
      path = "/Users/yuki/.ssh/config";
      mode = "0600";
    };
    "ssh-ed25519-private" = {
      sopsFile = ../../secrets/ssh-secrets.yaml;
      path = "/Users/yuki/.ssh/id_ed25519";
      mode = "0600";
    };
    "ssh-ed25519-public" = {
      sopsFile = ../../secrets/ssh-secrets.yaml;
      path = "/Users/yuki/.ssh/id_ed25519.pub";
      mode = "0644";
    };
  };

  programs.ssh = {
    enable = true;
    
    # 基本的なSSH設定（暗号化ファイルで上書き）
    matchBlocks = {
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
      };
    };
    
    # SSH クライアント設定
    extraConfig = ''
      # セキュリティ強化設定
      Protocol 2
      ServerAliveInterval 60
      ServerAliveCountMax 3
      
      # 暗号化アルゴリズム指定
      Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
      MACs umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com
      KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
    '';
  };

  # SSH鍵権限の適切な設定
  home.activation.fixSSHPermissions = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -d "/Users/yuki/.ssh" ]; then
      chmod 700 /Users/yuki/.ssh
      chmod 600 /Users/yuki/.ssh/id_* 2>/dev/null || true
      chmod 644 /Users/yuki/.ssh/*.pub 2>/dev/null || true
      chmod 600 /Users/yuki/.ssh/config 2>/dev/null || true
    fi
  '';
}
```

### Phase 3: 統合セキュリティ管理

#### 1. セキュリティヘルスチェック強化
```bash
#!/usr/bin/env bash
# scripts/git-ssh-security-check.sh

echo "🔐 Git & SSH Security Health Check"
echo "==================================="

# Git設定セキュリティチェック
echo "📝 Git Configuration:"
if [ -f ~/.config/git/user-name ]; then
    echo "✅ Git username: Encrypted"
else
    echo "❌ Git username: Not encrypted"
fi

if [ -f ~/.config/git/user-email ]; then
    echo "✅ Git email: Encrypted"
else
    echo "❌ Git email: Not encrypted"
fi

if [ -f ~/.config/git/github-token ]; then
    echo "✅ GitHub token: Encrypted"
else
    echo "❌ GitHub token: Not encrypted"
fi

# Git動作確認
echo ""
echo "🔧 Git Functionality:"
if git config user.name >/dev/null 2>&1; then
    echo "✅ Git user.name: Available"
else
    echo "❌ Git user.name: Not configured"
fi

if git config user.email >/dev/null 2>&1; then
    echo "✅ Git user.email: Available"
else
    echo "❌ Git user.email: Not configured"
fi

# SSH設定セキュリティチェック
echo ""
echo "🔑 SSH Configuration:"
if [ -f ~/.ssh/config ]; then
    perms=$(ls -l ~/.ssh/config | awk '{print $1}')
    if [[ $perms == "-rw-------"* ]]; then
        echo "✅ SSH config: Found with secure permissions (600)"
    else
        echo "⚠️  SSH config: Found but permissions $perms (should be 600)"
    fi
else
    echo "❌ SSH config: Missing"
fi

# SSH鍵確認
if [ -f ~/.ssh/id_ed25519 ]; then
    perms=$(ls -l ~/.ssh/id_ed25519 | awk '{print $1}')
    if [[ $perms == "-rw-------"* ]]; then
        echo "✅ SSH private key: Found with secure permissions (600)"
    else
        echo "⚠️  SSH private key: Found but permissions $perms (should be 600)"
    fi
else
    echo "❌ SSH private key: Missing"
fi

# GitHub接続テスト
echo ""
echo "🌐 GitHub Connectivity:"
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "✅ GitHub SSH: Authentication successful"
else
    echo "❌ GitHub SSH: Authentication failed"
fi

# Git操作テスト（非破壊的）
echo ""
echo "📊 Git Operations:"
if git ls-remote origin >/dev/null 2>&1; then
    echo "✅ Git remote access: Working"
else
    echo "❌ Git remote access: Failed"
fi
```

#### 2. 自動修復機能
```nix
# nix/common/security/auto-fix.nix
{ config, lib, pkgs, ... }:

{
  # 設定問題の自動修復
  home.activation.securityAutoFix = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "🔧 Running security auto-fix..."
    
    # SSH権限の自動修復
    if [ -d ~/.ssh ]; then
      find ~/.ssh -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
      find ~/.ssh -type f -name "*.pub" -exec chmod 644 {} \;
      [ -f ~/.ssh/config ] && chmod 600 ~/.ssh/config
      chmod 700 ~/.ssh
    fi
    
    # Git設定の整合性チェック
    if [ -f ~/.config/git/user-name ] && [ -f ~/.config/git/user-email ]; then
      # 必要に応じてgit configの更新
      git config --global user.name "$(cat ~/.config/git/user-name)" || true
      git config --global user.email "$(cat ~/.config/git/user-email)" || true
    fi
    
    echo "✅ Security auto-fix completed"
  '';
}
```

## 完了条件

### Git設定
- [ ] ユーザー情報がsops-nixで暗号化されている
- [ ] GitHub tokenが安全に管理されている
- [ ] Git操作が正常に動作する（認証、push/pull等）
- [ ] 単一の設定ソースから管理されている

### SSH設定
- [ ] SSH設定が暗号化されている
- [ ] SSH鍵が適切な権限で管理されている
- [ ] GitHub SSHが正常に動作する
- [ ] セキュリティ強化設定が適用されている

### セキュリティ
- [ ] 平文での機密情報保存が完全に排除されている
- [ ] バックアップ時に機密情報が漏洩しない
- [ ] 権限設定が適切に管理されている
- [ ] セキュリティヘルスチェックが全て通る

## 依存関係

- **sops-nix基盤**: todo-3の完了が前提
- **age暗号化**: 暗号化鍵の準備完了
- **.sops.yaml設定**: 暗号化ルールの設定完了

## 関連ファイル

- `nix/secrets/git-secrets.yaml` - Git関連シークレット
- `nix/secrets/ssh-secrets.yaml` - SSH関連シークレット
- `nix/common/development/git-secure.nix` - 安全なGit設定
- `nix/common/security/ssh-secure.nix` - 安全なSSH設定
- `scripts/git-ssh-security-check.sh` - セキュリティチェック

## 注意事項

### バックアップ戦略
- 既存設定の確実なバックアップ
- 暗号化前の設定内容保存
- 復旧手順の事前準備

### 段階実装
- 一度に全て変更せず段階的実装
- 各ステップでの動作確認
- ロールバック手順の準備

### テスト環境
- 本番環境での実装前にテスト
- 非破壊的テストでの事前確認
- CI/CD環境での検証

---

**作成日**: 2025年7月13日  
**最終更新**: 2025年7月13日  
**作成者**: Claude Code Assistant