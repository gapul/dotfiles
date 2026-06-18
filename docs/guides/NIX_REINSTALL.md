# Nix 再インストール手順（FileVault パスワード喪失時）

## 背景

macOS 起動時に「Enter a password to unlock the disk "Nix Store".」が表示される。

- `Nix Store` APFS ボリュームが FileVault で暗号化されているが、自動アンロック用のパスワードが `System.keychain` から失われている
- ボリュームのパスフレーズ自体も覚えていない
- → `changePassphrase` / `decryptVolume` どちらも使えないため、ボリュームを削除して Nix を再インストールする

## 前提・影響範囲

- `/nix` の中身（Nix store, profiles, daemon socket 等）は全て消える
- ユーザーの Nix 設定（`~/dotfiles/nix/`, `~/.config/nix/`, home-manager の設定など）は `/nix` の外なので**残る**
- 再インストール後、`darwin-rebuild switch` / `home-manager switch` 等で環境を復旧できる

## 環境確認結果（2026-05-13 時点）

```
APFS Volume:     disk3s7
Name:            Nix Store
FileVault:       Yes (Locked)
Mount Point:     Not Mounted
Capacity:        38.2 GB consumed
```

LaunchDaemons:
- `/Library/LaunchDaemons/systems.determinate.nix-daemon.plist`
- `/Library/LaunchDaemons/systems.determinate.nix-store.plist`
- `/Library/LaunchDaemons/systems.determinate.nix-installer.nix-hook.plist`
- `/Library/LaunchDaemons/org.nixos.activate-system.plist`

ユーザー/グループ:
- `_nixbld1` 〜 `_nixbld32`
- `nixbld` グループ

`/etc/fstab`:
```
UUID=2d153ec1-3f45-4049-9570-d844b25edbfa /nix apfs rw,noatime,noauto,nobrowse,nosuid,owners # Added by the Determinate Nix Installer
```

`/etc/synthetic.conf`:
```
nix
```

## 手順

### Step 1: LaunchDaemons の停止と削除

```bash
sudo launchctl bootout system/systems.determinate.nix-daemon 2>/dev/null
sudo launchctl bootout system/systems.determinate.nix-store 2>/dev/null
sudo launchctl bootout system/systems.determinate.nix-installer.nix-hook 2>/dev/null
sudo launchctl bootout system/org.nixos.activate-system 2>/dev/null

sudo rm /Library/LaunchDaemons/systems.determinate.nix-daemon.plist
sudo rm /Library/LaunchDaemons/systems.determinate.nix-store.plist
sudo rm /Library/LaunchDaemons/systems.determinate.nix-installer.nix-hook.plist
sudo rm /Library/LaunchDaemons/org.nixos.activate-system.plist
```

### Step 2: ロックされた APFS ボリュームを削除（不可逆）

パスワード不要。erase 扱いなので暗号化されていても削除できる。

```bash
# 念のため再確認
diskutil apfs list | grep -B 2 -A 8 "Nix Store"

# 削除実行
sudo diskutil apfs deleteVolume disk3s7
```

⚠️ disk identifier は環境によって変わる可能性があるため、必ず実行前に `diskutil apfs list` で確認すること。

### Step 3: マウント設定のクリーンアップ

```bash
# /etc/fstab から /nix 行を削除
sudo sed -i.bak '/\/nix /d' /etc/fstab

# /etc/synthetic.conf から nix 行を削除
sudo sed -i.bak '/^nix$/d' /etc/synthetic.conf

# 結果確認
cat /etc/fstab
cat /etc/synthetic.conf
```

### Step 4: _nixbld ユーザーとグループの削除

```bash
for i in $(seq 1 32); do
  sudo dscl . -delete /Users/_nixbld$i 2>/dev/null
done
sudo dscl . -delete /Groups/nixbld

# 確認
dscl . -list /Users | grep -i nix    # 何も出ないこと
dscl . -list /Groups | grep -i nix   # 何も出ないこと
```

### Step 5: シェル設定のバックアップ確認

Determinate Nix Installer は通常以下にバックアップを置く（あれば復元検討）:

```bash
ls /etc/zshrc.backup-before-nix 2>/dev/null
ls /etc/bashrc.backup-before-nix 2>/dev/null
ls /etc/bash.bashrc.backup-before-nix 2>/dev/null
ls /etc/zshenv.backup-before-nix 2>/dev/null
```

存在すれば:
```bash
sudo mv /etc/zshrc.backup-before-nix /etc/zshrc
# など
```

今回の環境ではバックアップは見つからなかった（クリーンアップ済みの可能性）。

### Step 6: 再起動

```bash
sudo reboot
```

再起動後、起動時のパスワードプロンプトが消えていることを確認。

### Step 7: Nix の再インストール（暗号化なし）

```bash
curl -fsSL https://install.determinate.systems/nix | sh -s -- install \
  --determinate \
  --no-confirm \
  --encrypt false
```

`--encrypt false` により `/nix` ボリュームは FileVault 暗号化されず、今後パスワード要求は発生しない。

### Step 8: 動作確認

```bash
nix --version
nix-store --version
ls /nix/store | head
```

### Step 9: dotfiles からの環境復旧

```bash
cd ~/dotfiles/nix
# 例（プロジェクト構成に合わせて調整）
nix run nix-darwin -- switch --flake .#<host>
# home-manager 利用時
home-manager switch --flake .#<user>
```

## トラブルシューティング

### `diskutil apfs deleteVolume` が失敗する

- 他のプロセスがボリュームを掴んでいる可能性 → `sudo lsof | grep /nix`
- それでもダメなら `diskutil unmountDisk force disk3s7` 後に再試行

### 再インストール後も `/nix` がマウントされない

- `/etc/synthetic.conf` の `nix` 行が再追加されているか確認
- `/etc/fstab` が更新されているか確認
- 反映には再起動が必要

### `_nixbld` ユーザーが残っている

- `sudo dscl . -delete /Users/_nixbldN` を個別に実行
- UID 重複時は再インストーラーが既存ユーザーを再利用するため必須ではない

## 参考

- Determinate Nix Installer: https://github.com/DeterminateSystems/nix-installer
- 公式アンインストールガイド（インストーラが動く場合）: `sudo /nix/nix-installer uninstall`
