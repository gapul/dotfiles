# NixOS / Windows デュアルブート 構築手順 (最大セキュリティ構成)

現在 Windows がフル構築済みの 1 台の SSD を**縮小して空き領域に NixOS を入れる**手順。
GPU は Intel 内蔵のみ前提。**両 OS とも暗号化 + 署名ブート**にする:

- NixOS root … **LUKS 全ディスク暗号化**
- ブート … **lanzaboote で Secure Boot 有効**（自分の鍵で署名、Microsoft 鍵も残して Windows 共存）
- Windows … BitLocker を**一時中断するだけ**（復号しない）で維持

設定は本 dotfiles の flake (`nix/`) に統合済み:

- `nix/hosts/nixos-laptop.nix` … システム設定 (lanzaboote / LUKS+TPM2 / zram / Intel GPU / Hyprland /
  fcitx5-mozc / tlp / fprintd / podman / tailscale / fwupd)
- `nix/flake.nix` の `nixosConfigurations."nixos-laptop"` … lanzaboote + home-manager を接続
  (`home/common.nix` + `home/linux.nix` + `home/hyprland.nix` リック + `home/dev.nix` + `home/restic-backup-linux.nix`)
- `nix/hosts/nixos-laptop-hardware.nix` … **実機で生成して後から追加**するマシン固有ファイル (LUKS デバイス UUID もここに入る)

> ⚠️ Windows を消さないこと。ESP (EFI システムパーティション) は**フォーマットせず流用**する。
> 各コマンドのディスク名 (`nvme0n1` / `sda` 等) は必ず `lsblk` で実機を確認してから実行する。

---

## Phase 0. Windows 側の事前準備 (最重要)

パーティション操作前にこれを怠ると Windows が起動不能になる。

1. **重要データのバックアップ**を取る。
2. **BitLocker を中断**（復号は不要）。管理者 PowerShell で:
   ```powershell
   manage-bde -status                       # 暗号化状態を確認
   (Get-BitLockerVolume -MountPoint C:).KeyProtector  # 回復キーを控える(必須)
   manage-bde -protectors -disable C: -RebootCount 0  # 再有効化まで中断したままにする
   ```
   > データは暗号化されたまま保持される。Secure Boot 切替やブートローダ追加で TPM 測定値が変わり、
   > 初回 Windows 起動時に**一度だけ回復キーを要求される**ことがあるので、回復キーは必ず手元に。
3. **高速スタートアップを無効化** (コントロールパネル → 電源オプション → 電源ボタンの動作 →
   「現在利用可能でない設定を変更します」→「高速スタートアップを有効にする」のチェックを外す)。
   切らないと Windows 休止中の NTFS がロック/未確定状態のままになり、Linux から触ると破損する。
   > これは**インストール作業中の一時的な措置**。本構成は NixOS から Windows NTFS を自動マウント
   > しない (`boot.supportedFilesystems` はコメントアウト) ので、**インストール後は再有効化してよい**
   > (Phase 9-2 参照)。C: を NixOS から読み書き共有する場合のみ OFF のまま運用する。
4. **休止状態を無効化** (任意だが推奨)。管理者 PowerShell で:
   ```powershell
   powercfg /h off
   ```
5. **C: を縮小**。`diskmgmt.msc` (ディスクの管理) → C: を右クリック →「ボリュームの縮小」→
   NixOS 用に空けたい容量 (例: 150000 MB ≒ 150GB) を指定。
   生成された**未割り当て領域はそのまま**にしておく (NixOS インストーラ側で切る)。

## Phase 1. BIOS / UEFI 設定

再起動して BIOS に入る (起動時 `Del` / `F2` 等)。

- **Secure Boot は一旦 OFF のまま**。鍵を自分で登録するまでは NixOS が起動できないため、
  インストール〜鍵登録 (Phase 8) の後で ON にする。
- **UEFI モードを維持** (CSM / Legacy にしない)。Windows は元々 UEFI なのでそのまま。
- USB から起動できるよう、必要なら Fast Boot を一時的に無効化。

## Phase 2. インストーラ USB を作る (Mac から)

インストール作業は全て CLI (cryptsetup / nixos-install --flake / sbctl) で、デスクトップ環境は
インストール後に flake から入るため、**minimal ISO** を使う (軽い・無駄が無い)。

1. ISO をダウンロードして SHA256 を照合 (`channels.nixos.org` の "latest" は最新ビルドに追従):
   ```sh
   cd ~/Downloads
   curl -L -o nixos-minimal-26.05-x86_64.iso \
     "https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso"
   curl -sL "https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso.sha256"
   shasum -a 256 nixos-minimal-26.05-x86_64.iso   # 上の値と一致を確認
   ```
2. USB を挿し、書き込む (macOS の `dd` は `status=progress` 非対応。進捗は `Ctrl+T`):
   ```sh
   diskutil list external physical          # USB の diskN を特定 (容量・Removable で判断)
   diskutil unmountDisk /dev/diskN
   sudo dd if=~/Downloads/nixos-minimal-26.05-x86_64.iso of=/dev/rdiskN bs=4m
   sync && diskutil eject /dev/diskN
   ```
   > `rdiskN` (raw) を使うと速い。`diskN` を間違えると別ディスクを破壊するので必ず確認。
   > 書込後に「The disk you attached was not readable」が出たら **Ignore** (Initialize は押さない)。

## Phase 3. インストーラを起動

USB を挿して PC を起動 → 起動メニュー (`F12` / `F8` / `Esc` / `F11` 等) で **UEFI: USB...** を選択。
minimal はテキストのログイン画面。`sudo -i` で root になり、`nmtui` 等で有線/Wi-Fi を接続しておく。

## Phase 4. パーティション作成 + LUKS 暗号化

```sh
sudo -i
lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME,MOUNTPOINT
```

典型的な既存構成 (NVMe の例):

| パーティション | 用途 | 触り方 |
|---|---|---|
| `nvme0n1p1` | ESP (vfat, ~100–300MB) | **流用** (フォーマット禁止) |
| `nvme0n1p2` | Microsoft 予約 (MSR) | 触らない |
| `nvme0n1p3` | Windows C: (ntfs) | 触らない |
| `nvme0n1p4` | 回復 (ntfs) | 触らない |
| 末尾の空き | Phase 0 で空けた領域 | ここに NixOS root を作る |

空き領域に新パーティションを作成 (タイプは `Linux filesystem`):
```sh
cfdisk /dev/nvme0n1      # [New] → 全空き容量 → [Type: Linux filesystem] → [Write] → yes → [Quit]
```

作られた番号を `lsblk` で再確認 (ここでは `nvme0n1p5` と仮定)。**LUKS で暗号化**してから ext4 を作る:
```sh
cryptsetup luksFormat /dev/nvme0n1p5         # パスフレーズを設定 (YES と大文字確認あり)
cryptsetup open /dev/nvme0n1p5 cryptroot     # /dev/mapper/cryptroot として開く
mkfs.ext4 -L nixos /dev/mapper/cryptroot
```

> スワップは**平文パーティションを作らない**。host 設定で `zramSwap.enable = true;` 済み
> (メモリ内・暗号化された RAM 上)。物理スワップが要る場合のみ、別途暗号化スワップを構成する。

## Phase 5. マウント (ESP は流用)

```sh
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot        # ← 既存 Windows ESP。フォーマットしない！
```

> ESP が 100MB しかない場合、署名 UKI で埋まりやすい。`nix/hosts/nixos-laptop.nix` の
> `boot.lanzaboote.configurationLimit` を 3〜5 に下げておくと安全 (260MB 以上あれば 8 のままで可)。

## Phase 6. ハードウェア設定を生成し、flake を取り込む

```sh
nixos-generate-config --root /mnt
```

`/mnt/etc/nixos/hardware-configuration.nix` が生成される。`cryptroot` を開いた状態で実行したので、
中に **`boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/…";`** が自動で入る。
あわせて `fileSystems."/boot"` が ESP (vfat)、`fileSystems."/"` が `/dev/mapper/cryptroot` を
指していることを確認する。

dotfiles を取り込み、生成したハード設定をリポジトリ内の所定名にコピー:
```sh
nix-shell -p git
git clone https://github.com/gapul/dotfiles.git /mnt/etc/nixos/dotfiles
cp /mnt/etc/nixos/hardware-configuration.nix \
   /mnt/etc/nixos/dotfiles/nix/hosts/nixos-laptop-hardware.nix
git -C /mnt/etc/nixos/dotfiles add -A      # flake は git 追跡ファイルしか含めないため必須
```

> この `nixos-laptop-hardware.nix` が存在して初めて flake に `nixosConfigurations."nixos-laptop"` が
> 生える設計 (Mac 側 `nix flake check` を壊さないため)。

## Phase 7. インストール

この時点では **Secure Boot はまだ OFF**。lanzaboote の鍵が未登録なので OFF のまま入れる。
```sh
nixos-install --flake /mnt/etc/nixos/dotfiles/nix#nixos-laptop
```

- 途中で **root パスワード**を聞かれる。
- 通常ユーザー (`gapul`) のパスワードを設定:
  ```sh
  nixos-enter --root /mnt -c 'passwd gapul'
  ```

完了したら再起動:
```sh
reboot      # USB を抜く
```

## Phase 8. 初回起動後 → Secure Boot を有効化

systemd-boot ベースのメニューに **NixOS** と **Windows Boot Manager** が並ぶ。
起動時に LUKS パスフレーズを聞かれる → NixOS にログイン。

### 8-1. Secure Boot 鍵を作って署名・登録

```sh
# 鍵を生成 (host 設定の pkiBundle = /var/lib/sbctl と一致)
sudo sbctl create-keys

# lanzaboote は既に有効なので、再ビルドで UKI が自分の鍵で署名される
sudo nixos-rebuild switch --flake ~/.dotfiles/nix#nixos-laptop
sudo sbctl verify        # 署名済みファイルが ✓ で並ぶことを確認
```

### 8-2. BIOS を「Setup Mode」にして鍵を登録

1. 再起動して BIOS へ。**Secure Boot の鍵をクリア / Setup Mode に**する
   (メーカーにより "Erase all Secure Boot keys" / "Clear keys" / "Setup Mode")。
2. NixOS に戻り、Microsoft 鍵を**残したまま**自分の鍵を登録:
   ```sh
   sudo sbctl enroll-keys --microsoft   # -m: MS 鍵を残し Windows の起動を維持
   ```

### 8-3. Secure Boot を ON

1. 再起動して BIOS で **Secure Boot を Enabled** に戻す。
2. NixOS 起動後に確認:
   ```sh
   bootctl status   # "Secure Boot: enabled (user)" になっていれば成功
   ```
   Windows も Boot Manager から起動できることを確認 (MS 鍵を残したので通る)。

### 8-4. その他

- **時計ズレ対策** (NixOS は RTC=UTC、Windows は既定でローカル時刻)。Windows の管理者 PowerShell で:
  ```powershell
  reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
  ```
- **BitLocker を再有効化**。Phase 0 で中断したので Windows 側で戻す:
  ```powershell
  manage-bde -protectors -enable C:
  ```
- **age 鍵の配置**: home-manager に `sops-nix` を入れているため、暗号化シークレットを使う場合は
  `~/.config/sops/age/keys.txt` (または `SOPS_AGE_KEY_FILE`) に鍵を置く。鍵が無く復号で詰まる場合は、
  当面 `nix/flake.nix` の該当 `imports` から `sops-nix.homeManagerModules.sops` を一時的に外してもよい。

## Phase 9. 以降の運用

設定変更は Mac と同じく flake から。lanzaboote が**毎回自動で署名**するので Secure Boot は維持される:
```sh
sudo nixos-rebuild switch --flake ~/.dotfiles/nix#nixos-laptop
```

`nix/hosts/nixos-laptop-hardware.nix` をリポジトリに**コミット**しておけば以後そのまま再構築できる
(LUKS デバイスの UUID とデバイスパスのみ。鍵そのものは含まれないので公開リポでも問題は小さいが、
気になるなら `.gitignore` してローカル保持も可)。

### 9-1. 両 OS を日常的に使うための小ワザ

Windows と NixOS を両方使う前提なので、切替コストを下げる運用を入れておく。

- **NixOS から直接 Windows へ再起動**（systemd-boot のメニューを待たずに済む）:
  ```sh
  # 次回だけ Windows で起動して再起動
  sudo bootctl set-oneshot auto-windows && systemctl reboot
  # もしくは
  sudo systemctl reboot --boot-loader-entry=auto-windows
  ```
  エントリ名は `bootctl list` で確認できる (`auto-windows` が標準)。
- **メニュー表示時間**は `boot.loader.timeout = 5;` 済み。取り逃したらもう一度再起動でOK。
- **Secure Boot 鍵をバックアップ**しておくと、BIOS 更新等で鍵が飛んでも復旧が速い:
  ```sh
  sudo tar czf ~/sbctl-keys-backup.tar.gz -C /var/lib sbctl   # 安全な場所/USB に退避
  ```
- **共有ファイル**は NTFS を Linux から書き込むより、両 OS が安全に読み書きできる
  **exFAT の共有パーティション**を 1 つ用意する方が破損リスクが無い (休止状態の影響も受けない)。
  必要になったら空き領域に `mkfs.exfat` で作る。

### 9-2. 高速スタートアップを戻す (任意)

Phase 0-3 で切った高速スタートアップは、**NixOS から Windows C: (NTFS) を触らない運用なら戻してよい**。
危険なのは「Windows 休止状態の NTFS を Linux から書き込む」ケースだけで、本構成はそれを避けている。
Windows の管理者 PowerShell で:
```powershell
powercfg /h on
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 1 /f
```
※ 将来 C: を NixOS から読み書き共有したくなったら、再び OFF にすること。

### 9-3. インストール後の初回セットアップ (一度だけ)

flake に組み込んだ各機能の有効化に必要な手動ステップ。

```sh
# 指紋を登録 (fprintd)。以後 sudo / hyprlock で指紋が使える
sudo fprintd-enroll $USER

# Tailscale に参加 (homelab *.gapul.net)
sudo tailscale up

# TPM2 自動解錠を登録 (※ Secure Boot を ON にした後で。付録 A)
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p5

# restic バックアップの前提: rclone google-drive を再認証 → sops に token を入れる
rclone authorize "drive"   # 出力 token を secrets.yaml の rclone_conf へ
# 初回バックアップは systemd timer (日次13:00) を待つか、手動起動:
systemctl --user start restic-backup.service

# age 鍵 (sops 復号用) を ~/.config/sops/age/keys.txt に配置 (無いと restic 等が止まる)
```

Hyprland の主なキーバインド (`home/hyprland.nix`): `SUPER+Return`=ghostty, `SUPER+R`=wofi,
`SUPER+Q`=閉じる, `SUPER+F`=全画面, `SUPER+L`=ロック, `SUPER+E`=yazi, `SUPER+P`=範囲スクショ,
`SUPER+C`=クリップボード履歴, `SUPER+1..0`=ワークスペース。5/15 分でロック/サスペンド (hypridle)。

---

## 付録 A: TPM2 自動解錠 (パスフレーズ入力を省く)

**設定は組込済み**。`nixos-laptop.nix` で `boot.initrd.systemd.enable = true;` と
`boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ];` を有効にしてある。
あとは **Secure Boot を有効化した後 (Phase 8 完了後)** に、TPM へ鍵を登録するだけ:

```sh
# 対象 LUKS パーティションに TPM2 を登録 (PCR 7 = Secure Boot 状態に束縛)
# パーティションは lsblk で確認 (例: nvme0n1p5)。現在のパスフレーズを聞かれる。
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p5
```

これで次回起動から TPM が自動解錠する。ブート列が改ざんされると PCR 7 が変わり TPM は鍵を出さない
(= 安全に省略できる)。登録前やブート改ざん時はパスフレーズ入力にフォールバックする。

> ⚠️ **Secure Boot を有効化する前に登録しないこと**。PCR 7 の値が Secure Boot OFF 状態で固定され、
> 後で ON にすると解錠できなくなる。必ず Phase 8 (Secure Boot ON) の後で登録する。

## 付録 B: トラブルシュート

| 症状 | 対処 |
|---|---|
| Windows 起動時に BitLocker 回復キーを要求される | Phase 0 で控えたキーで解錠。TPM 測定変化による一度きりの想定 |
| `bootctl status` が "Secure Boot: disabled" | Phase 8-2/8-3 の鍵登録 or BIOS の Enable 漏れ。`sbctl verify` で署名確認 |
| Secure Boot ON 後 NixOS が起動しない | BIOS を Setup Mode に戻し `sbctl enroll-keys -m` をやり直す。最悪 Secure Boot を OFF にすれば起動可 |
| Windows が起動しない (Secure Boot ON) | `enroll-keys` で `--microsoft` を付け忘れ。再登録する |
| メニューに Windows が出ない | ESP を `/mnt/boot` に正しくマウントしたか確認。別 ESP に入れていないか |
| ESP 容量不足で switch が失敗 | `boot.lanzaboote.configurationLimit` を下げる / `nix-collect-garbage -d` で古い世代削除 |
| LUKS パスフレーズを毎回聞かれて面倒 | 付録 A の TPM2 自動解錠を設定 |
| Intel GPU で画面が出ない | `nixos-laptop.nix` の `hardware.graphics` を確認。最悪 `nomodeset` で起動して調査 |
