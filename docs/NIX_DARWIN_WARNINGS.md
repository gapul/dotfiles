# nix-darwin Warning解決ガイド

## Warning: `$HOME ('/Users/yuki') is not owned by you`

### 問題
```bash
sudo nix run nix-darwin -- switch --flake . --impure
```
実行時に以下のwarningが表示される：
```
warning: $HOME ('/Users/yuki') is not owned by you, falling back to the one defined in the 'passwd' file ('/var/root')
```

### 原因
- sudoで実行すると、HOMEディレクトリがrootユーザーのものとして認識される
- nix-darwinがユーザーのHOMEディレクトリにアクセスする際の権限問題

### 解決方法

#### 1. 環境変数を明示的に渡す (推奨)
```bash
sudo env HOME="/Users/yuki" USER="yuki" nix run nix-darwin -- switch --flake . --impure
```

#### 2. justfileコマンドを使用
```bash
just rebuild-darwin-sudo
```

#### 3. スクリプト実行
```bash
./scripts/nix-darwin-switch.sh
```

#### 4. sudoers設定 (上級者向け)
```bash
sudo visudo -f /etc/sudoers.d/nix-darwin
```
以下を追加：
```
%admin ALL=(ALL) SETENV: /nix/store/*/bin/darwin-rebuild
```

### 確認方法
Warning表示なしで以下が実行されることを確認：
1. System activation完了
2. Home Manager activation完了
3. 設定反映確認

### 注意事項
- この問題は機能には影響しない（warning のみ）
- システム設定は正常に適用される
- Performance moduleも正常に動作する

### 関連ファイル
- `justfile`: rebuild-darwin-sudo コマンド
- `scripts/nix-darwin-switch.sh`: Warning回避スクリプト
- `nix/flake.nix`: environment.variables設定