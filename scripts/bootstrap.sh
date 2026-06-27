#!/usr/bin/env bash
#
# 新しい Mac で 0 → 1 セットアップ。
# 想定: 工場出荷状態 + Apple ID ログイン + FileVault on 直後。
#
# 流れ:
#   1. Xcode Command Line Tools (git/curl/etc. のため)
#   2. Determinate Nix install
#   3. ~/.dotfiles を git clone
#   4. age 秘密鍵を ~/.config/sops/age/keys.txt に配置 (手動 paste 待ち)
#   5. nix run nix-darwin -- switch
#   6. 各 third-party brew tap を trust
#   7. nix run home-manager -- switch
#   8. brew uninstall (Nix側に移行した重複)
#
# 何度走らせても安全 (idempotent)。

set -euo pipefail

log() { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[bootstrap]\033[0m %s\n' "$*" >&2; }

# Fork した時はこの URL を自分の repo に変える(or nix/user.nix の dotfilesRepo を参照)
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/gapul/dotfiles.git}"
DOTFILES_DIR="$HOME/.dotfiles"
SOPS_KEY="$HOME/.config/sops/age/keys.txt"

# 1. Xcode CLT
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools (GUI が立ち上がる)..."
  xcode-select --install || true
  until xcode-select -p >/dev/null 2>&1; do
    sleep 5
    log "  ... 待機中"
  done
fi
log "Xcode CLT OK"

# 2. Determinate Nix
if ! command -v nix >/dev/null && [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  log "Installing Determinate Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
    sh -s -- install --no-confirm
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
  log "Determinate Nix already installed"
fi

# Ensure nix in PATH for the rest of this script
if ! command -v nix >/dev/null; then
  export PATH="/nix/var/nix/profiles/default/bin:$PATH"
fi

# 2.5. /nix ボリュームを起動序盤に確実にマウントさせる (Login Items 対策)
#
# Determinate のデフォルト構成:
#   - /nix ボリュームを FileVault 暗号化
#   - /etc/fstab に noauto を付与
#   - launchd デーモン org.nixos.darwin-store が遅延マウント
# 結果: Login Items の Ghostty / AeroSpace 等が起動した時点で /nix がまだマウントされず、
#       symlink 先 (/nix/store/...) が読めず config 読み込み失敗
#
# 対策: ボリューム復号化 + fstab から noauto 削除 → macOS automountd が起動序盤にマウント
# トレードオフ: Determinate 公式サポート外設定。セキュリティ的には FileVault でカバー済
#               (/nix の中身は公開バイナリなので二重暗号化に実害価値なし)
#
# 暗号化チェック
if diskutil apfs list 2>/dev/null | grep -A 6 "Nix Store" | grep -q "FileVault: *Yes"; then
  log "/nix ボリュームが暗号化されてます。Login Items 競合を避けるため復号化します..."
  # ボリュームパスワードを System keychain から取得
  NIX_VOL_PW=$(sudo security find-generic-password -s "Nix Store" -a "Nix Store" -w \
                /Library/Keychains/System.keychain 2>/dev/null || true)
  if [ -z "$NIX_VOL_PW" ]; then
    err "  System keychain に Nix Store のパスワードが見つかりません"
    err "  Keychain Access で 'Nix Store' エントリを開いて password を取り出してから手動で:"
    err "    sudo diskutil apfs decryptVolume \"Nix Store\""
    exit 1
  fi
  printf '%s' "$NIX_VOL_PW" | sudo diskutil apfs decryptVolume "Nix Store" -stdinpassphrase
  log "復号化完了 (AES ハードウェアアクセラレーションで一瞬で終わるはず)"
fi

# fstab の noauto を削除
if grep -q "noauto" /etc/fstab 2>/dev/null; then
  log "/etc/fstab から noauto を削除して起動時自動マウントを有効化..."
  sudo cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
  sudo sed -i '' 's/,noauto//' /etc/fstab
  log "  修正後: $(grep '/nix' /etc/fstab)"
fi

# 3. dotfiles clone
if [ ! -d "$DOTFILES_DIR/.git" ]; then
  log "Cloning dotfiles..."
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
  log "dotfiles already present, pulling..."
  git -C "$DOTFILES_DIR" pull --rebase
fi

# 4. age 秘密鍵
if [ ! -f "$SOPS_KEY" ]; then
  mkdir -p "$(dirname "$SOPS_KEY")"
  chmod 700 "$(dirname "$SOPS_KEY")"
  err "age 秘密鍵が見つかりません:"
  err "  Bitwarden 等で保管している自分の age 秘密鍵を、"
  err "  Notes の中身を $SOPS_KEY に貼り付けて save してください。"
  err "  終わったら本スクリプトを再実行 (それ以降から resume)."
  exit 1
fi
chmod 600 "$SOPS_KEY"
log "SOPS age key OK"

# 4.5. SSH 秘密鍵 (clone は HTTPS で済むが、commit 署名 / 将来の SSH push に必要)
SSH_PRIV="$HOME/.ssh/id_ed25519"
SSH_PUB="$HOME/.ssh/id_ed25519.pub"
SSH_ALLOWED="$HOME/.ssh/allowed_signers"
if [ ! -f "$SSH_PRIV" ]; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  err "SSH 秘密鍵 ($SSH_PRIV) が見つかりません:"
  err "  Bitwarden 等で保管している自分の ed25519 秘密鍵を貼り付けて save、"
  err "  終わったら 'chmod 600 $SSH_PRIV' してから本スクリプトを再実行."
  exit 1
fi
chmod 600 "$SSH_PRIV"
# .pub を秘密鍵から再生成 (古い不整合 .pub 残骸対策)
ssh-keygen -y -f "$SSH_PRIV" > "$SSH_PUB"
chmod 644 "$SSH_PUB"
# allowed_signers (git の SSH 署名検証用)
if [ ! -f "$SSH_ALLOWED" ]; then
  EMAIL=$(nix eval --raw -f "$DOTFILES_DIR/nix/user.nix" gitEmail 2>/dev/null || echo "92638132+gapul@users.noreply.github.com")
  echo "$EMAIL $(awk '{print $1, $2}' "$SSH_PUB")" > "$SSH_ALLOWED"
  chmod 600 "$SSH_ALLOWED"
fi
log "SSH key + allowed_signers OK"

# 5. system 設定 (sudo パスワード要)
log "darwin-rebuild switch (sudo パスワード入力あり)..."
sudo nix run nix-darwin/nix-darwin-26.05 -- switch --flake "$DOTFILES_DIR/nix#$(whoami)"

# 6. 第三者 tap の cask 信頼
log "Trusting third-party brew taps..."
# NOTE: この一覧は nix/hosts/darwin.nix の homebrew.taps と一致させること
for tap in deskflow/tap felixkratz/formulae finnvoor/tools gerlero/openfoam \
           gapul/kdeconnect nikitabobko/tap pear-devs/pear voicevox/voicevox \
           gapul/openutau gapul/zrythm gapul/azoo-key-skkserv; do
  brew trust "$tap" 2>/dev/null || true
done

# 7. home-manager switch (ユーザー権限で実行、sudo 禁止)
log "home-manager switch..."
nix run home-manager/release-26.05 -- switch --flake "$DOTFILES_DIR/nix#$(whoami)" -b backup

# 8. brew 重複の uninstall (Nix 管理に移行済のもの)
log "Cleaning duplicates installed by both brew and Nix..."
brew uninstall starship fzf atuin 2>/dev/null || true

# 9. uv tool で入れる CLI (brew/nix に無いもの)
log "Installing uv tools (gita, etc.)..."
uv tool install gita 2>&1 | tail -3 || true

# 10. ghq 配下の全 repo を gita に登録 (空でも安全)
if command -v gita >/dev/null && command -v ghq >/dev/null; then
  log "Registering ghq repos with gita..."
  ghq list -p 2>/dev/null | xargs -I {} gita add {} 2>&1 | tail -3 || true
fi

# 11. SKK 公開辞書を ~/.skk/ に install (skkeleton 用)
log "Installing SKK public dictionaries..."
bash "$DOTFILES_DIR/scripts/install-skk-dicts.sh" || true

# 12. gh auth (ブラウザ認証、未済なら起動)。SSH 鍵管理用 scope も要求
GH_SCOPES="admin:public_key,admin:ssh_signing_key"
if command -v gh >/dev/null; then
  if ! gh auth status >/dev/null 2>&1; then
    log "gh auth login (ブラウザが開きます。SSH 鍵で認証推奨)..."
    gh auth login -h github.com -p https -w -s "$GH_SCOPES" || true
  else
    # 既に auth 済でも、SSH 鍵 scope が無ければ refresh
    if ! gh auth status 2>&1 | grep -q "admin:ssh_signing_key"; then
      log "gh の SSH 鍵管理用 scope を追加..."
      gh auth refresh -h github.com -s "$GH_SCOPES" || true
    fi
  fi
fi

# 12.5. GitHub に SSH 鍵を auth + signing 両方として登録 (べき等、既存ならスキップ)
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1 && [ -f "$SSH_PUB" ]; then
  KEY_BODY=$(awk '{print $1, $2}' "$SSH_PUB")
  HOST_LABEL="$(hostname -s)"
  # auth key 重複チェック
  if ! gh ssh-key list --json key --jq '.[].key' 2>/dev/null | grep -qF "$KEY_BODY"; then
    log "GitHub に SSH 鍵を Authentication として登録: $HOST_LABEL"
    gh ssh-key add "$SSH_PUB" --title "$HOST_LABEL" || true
  fi
  # signing key 重複チェック
  if ! gh api /user/ssh_signing_keys --jq '.[].key' 2>/dev/null | grep -qF "$KEY_BODY"; then
    log "GitHub に SSH 鍵を Signing として登録: $HOST_LABEL (signing)"
    gh api -X POST /user/ssh_signing_keys \
      -f "title=$HOST_LABEL (signing)" \
      -f "key=$(cat "$SSH_PUB")" >/dev/null || true
  fi
fi

# 13. 残った手動 GUI ステップを ~/POST-BOOTSTRAP.md に書き出す
POST_FILE="$HOME/POST-BOOTSTRAP.md"
cat > "$POST_FILE" <<'EOF'
# 新 Mac セットアップ — 手動 GUI ステップ

bootstrap.sh 完了後、以下を順に GUI で実行してください。

## 1. App 権限付与 (System Settings → Privacy & Security)

下のコマンドで該当 pane を直接開けます:

```bash
# アクセシビリティ
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
# 画面収録
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
# 入力監視
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
# フルディスクアクセス
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
```

### アクセシビリティ
- [ ] AeroSpace
- [ ] AltTab
- [ ] Karabiner-Elements (Karabiner-VirtualHIDDevice-Daemon も)
- [ ] Mos
- [ ] Shortcat
- [ ] sketchybar (felixkratz)

### 画面収録
- [ ] AltTab
- [ ] AeroSpace (Workspace 切替時の preview に必要)

### 入力監視
- [ ] Karabiner-Elements
- [ ] Mos

### フルディスク
- [ ] iTerm/Ghostty (任意、~/Library 直下を grep したい時)

## 2. macSKK Input Source 登録
```bash
open "x-apple.systempreferences:com.apple.preference.keyboard?InputSources"
```
- Edit → `+` → Japanese → macSKK
- メニューバーの IME アイコン → macSKK を選んで切替

## 3. macSKK 辞書登録
```bash
bash ~/.dotfiles/scripts/install-skk-dicts-macskk.sh
```
その後 macSKK 設定 → Dictionaries → 5 辞書全部の Toggle を ON。

## 4. Plash website 再追加
1. Plash menubar → Settings → Display → "+"
2. Browse... ボタンで `~/.dotfiles/configs/wallpaper/aurora.html` を選択
   (security-scoped bookmark を取るため、Browse 経由が必須。直接 URL 貼付は NG)

## 5. AeroSpace 起動許可
- 初回起動時に macOS から「アクセシビリティ要求」が出る → 許可

## 6. Karabiner-Elements 起動許可
- 初回起動時に System Extension の許可
```bash
open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
```

## 7. GitHub SSH 鍵登録 — **bootstrap.sh で自動済み**
(Step 12.5 で auth + signing 両方を登録)
未登録の場合のみ手動で:
```bash
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname -s)"
gh api -X POST /user/ssh_signing_keys \
  -f title="$(hostname -s) (signing)" \
  -f key="$(cat ~/.ssh/id_ed25519.pub)"
```

## 8. macOS Login Items 確認
- home-manager activation で AeroSpace と Ghostty が登録済のはず
- System Settings → General → Login Items で確認

---

完了したら本ファイルを削除してください: `rm ~/POST-BOOTSTRAP.md`
EOF

log "完了! 新しいシェルを開いてください:"
log "  exec zsh"
log ""
log "★ 残りの手動 GUI ステップは $POST_FILE を参照"
