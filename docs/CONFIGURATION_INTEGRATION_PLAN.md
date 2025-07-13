# 設定ファイル統合計画

## 📋 概要

dotfilesに統合すべき設定ファイルの段階的統合計画です。

## ✅ Phase 1: 完了済み（2025年7月13日）

### AeroSpace設定統合
- **ファイル**: `~/.config/aerospace/aerospace.toml` → `configs/wm/aerospace/`
- **Nixモジュール**: `nix/common/desktop/aerospace.nix`
- **機能**: 
  - 設定ファイルリンク
  - ヘルスチェックスクリプト
  - 再起動スクリプト

### WezTerm設定統合  
- **ファイル**: `~/.config/wezterm/wezterm.lua` → `configs/terminals/wezterm/`
- **Nixモジュール**: `nix/common/terminals/wezterm.nix`
- **機能**:
  - 設定ファイルリンク
  - ヘルスチェックスクリプト
  - テーマ切り替えスクリプト

## 🔒 Phase 2: セキュリティ考慮（今後実装）

### Git設定統合
**現状**: 設定が分散している
```
~/.gitconfig         # ユーザー情報とLFS設定のみ
~/.config/git/config # メイン設定（Nixで生成済み）
```

**統合計画**:
1. `.gitconfig`の内容を`nix/common/development/default.nix`に移行
2. ユーザー情報はsops-nixで暗号化管理
3. 単一の設定ソースに統合

**実装予定**:
```nix
# nix/common/development/git.nix
programs.git = {
  userName = "gapul";  # sops-nixで暗号化
  userEmail = "yuk8337@gmail.com";  # sops-nixで暗号化
  lfs.enable = true;
  # 既存の設定を統合
};
```

### SSH設定管理
**現状**: 平文でSSH設定が存在
```
~/.ssh/config        # GitHub接続設定
~/.ssh/id_*          # SSH鍵ファイル
```

**統合計画**:
1. SSH設定をsops-nixで暗号化
2. SSH鍵の安全な管理方法確立
3. 設定テンプレートの作成

**実装予定**:
```nix
# nix/common/security/ssh.nix
sops.secrets."ssh/github-key" = {
  path = "/Users/yuki/.ssh/id_rsa";
  mode = "0600";
};

programs.ssh = {
  enable = true;
  matchBlocks = {
    "github.com" = {
      hostname = "github.com";
      user = "git";
      identityFile = "~/.ssh/id_rsa";
    };
  };
};
```

## 🔐 Phase 3: 高度なセキュリティ（オプション）

### GPG設定管理
**現状**: GPG設定と鍵が暗号化されていない
```
~/.gnupg/            # GPG鍵と設定
```

**統合計画**:
1. GPG鍵のバックアップ戦略
2. sops-nixでの設定暗号化
3. 自動鍵インポート機能

**実装予定**:
```nix
# nix/common/security/gpg.nix
programs.gpg = {
  enable = true;
  settings = {
    # GPG設定
  };
};

sops.secrets."gpg/private-key" = {
  path = "/Users/yuki/.gnupg/private-key.asc";
  mode = "0600";
};
```

## 📊 実装優先度

| Phase | 項目 | 優先度 | 理由 |
|-------|------|--------|------|
| 1 | AeroSpace/WezTerm | ✅ 完了 | 日常使用頻度が高い |
| 2 | Git設定統合 | 🔴 高 | 開発作業に必須 |
| 2 | SSH設定暗号化 | 🟡 中 | セキュリティ向上 |
| 3 | GPG設定管理 | 🟢 低 | 高度なセキュリティ要件 |

## 🛠️ 次のステップ

### Phase 2実装時の作業手順
1. sops-nixの初期設定確認
2. 秘密鍵の生成と設定
3. Git設定の段階的移行
4. SSH設定の暗号化
5. テストとバリデーション

### 注意事項
- **バックアップ必須**: 統合前に既存設定をバックアップ
- **段階実装**: 一度に全て変更せず、段階的に実施
- **テスト環境**: 本番環境前にテスト環境で検証
- **ロールバック計画**: 問題発生時の復旧手順を準備

## 📝 参考資料

- [sops-nix documentation](https://github.com/Mic92/sops-nix)
- [Home Manager SSH configuration](https://nix-community.github.io/home-manager/options.html#opt-programs.ssh.enable)
- [Home Manager Git configuration](https://nix-community.github.io/home-manager/options.html#opt-programs.git.enable)

---

*最終更新: 2025年7月13日*
*Phase 1完了: AeroSpace・WezTerm統合済み*