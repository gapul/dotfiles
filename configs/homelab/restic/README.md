# restic オフサイトバックアップ (共有リポジトリ)

母艦Mac / pve / macmini / rpi4 が **同一の暗号化 restic リポジトリ**を共有する:
`rclone:google-drive:restic-backup` (Google Drive 上、rclone 経由)。host 名で相乗り・重複排除。

| ホスト | 対象 | スケジュール | 実装 | 秘密の場所 |
|---|---|---|---|---|
| 母艦 (MacBook-Mini) | Documents/Pictures/Downloads/Movies/Music/Minecraft | 日次 13:00 | home-manager `nix/home/restic-backup.nix` (launchd) | sops-nix |
| pve | `/var/lib/vz/dump` (vzdump) | 日次 03:00 | `/usr/local/bin/restic-pve-offsite.sh` + systemd (git管理外・HOMELAB.md §10) | `/root/.config/rclone/rclone.conf` + `/root/.restic.pw` |
| macmini | `~/Developer` (除外: node_modules/.venv/target/.git/objects/モデル等) | 日次 05:00 | `restic-macmini-offsite.sh` + `local.restic-macmini.plist` (launchd) | 手動配置の生ファイル (sops 非導入) |
| rpi4 | `/home/pi` (docker サービスデータ) | 日次 04:30 | `restic-rpi-offsite.sh` + systemd timer | `/root/.config/rclone/rclone.conf` + `/root/.restic.pw` |

- 秘密はどれも `rclone.conf`(GDrive トークン) と restic パスワードで、**このリポジトリには含めない**(sops 経由 or 手動配置)。
- **共有リポジトリなので `restic forget` は必ず `--host <自ホスト>` スコープ**にする。**prune は母艦の日次のみ**が実行し、他ホストは prune しない(排他ロック競合を避ける)。
- Google OAuth は Production 公開済みでトークンは失効しない(以前は Testing のため約7日で失効し全ホスト停止した罠あり)。

## デプロイ手順

### rpi4 (Debian/aarch64)
```sh
sudo apt-get install -y restic rclone
# 秘密を配置: /root/.config/rclone/rclone.conf , /root/.restic.pw (母艦 sops から)
# ntfy 通知用: /root/.config/ntfy/{url,token}
sudo install -m755 restic-rpi-offsite.sh /usr/local/bin/restic-rpi-offsite.sh
sudo install -m644 restic-rpi-offsite.service restic-rpi-offsite.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now restic-rpi-offsite.timer
```

### macmini (nix-darwin だが sops 非導入のため imperative)
```sh
nix profile install nixpkgs#restic nixpkgs#rclone   # bin=~/.local/state/nix/profiles/profile/bin
# 秘密を配置: ~/.config/rclone/rclone.conf , ~/.config/restic/password , ~/.config/ntfy/{url,token}
install -m755 restic-macmini-offsite.sh ~/.local/bin/restic-macmini-offsite.sh
cp local.restic-macmini.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/local.restic-macmini.plist
# 初回: launchctl start local.restic-macmini
```
※ 将来的に nix-darwin モジュール化すると宣言的になる(現状は imperative)。

## スマホから中身を閲覧 (files.gapul.net)

暗号化リポジトリは Google Drive 上では中身が見えない。プレビューは pve ホスト上の
**restic mount (read-only FUSE) + Filebrowser** で行う。Caddy (CT103) が `files.gapul.net` で公開。

```sh
# pve ホスト:
install -m755 <filebrowser binary> /usr/local/bin/filebrowser   # github releases
install -m644 restic-view-mount.service restic-view-fb.service /etc/systemd/system/
# Filebrowser DB 初期化 (noauth / read-only / root=/mnt/restic-view / :8082):
filebrowser config init -d /etc/restic-view/filebrowser.db
filebrowser config set  -d /etc/restic-view/filebrowser.db --auth.method=noauth --root /mnt/restic-view --address 0.0.0.0 --port 8082 --perm.create=false --perm.rename=false --perm.modify=false --perm.delete=false --perm.share=false
filebrowser users add viewer <12文字以上pw> -d /etc/restic-view/filebrowser.db --perm.admin=false --perm.create=false --perm.rename=false --perm.modify=false --perm.delete=false --perm.share=false
systemctl daemon-reload && systemctl enable --now restic-view-mount.service restic-view-fb.service
```
- restic mount は **`--no-lock` 必須**(常駐マウントのロックが母艦の日次 prune を塞ぐのを防ぐ)。`RESTIC_CACHE_DIR=/var/cache/restic` で高速化。
- Caddy: `files.gapul.net → 192.168.116.100:8082` (../caddy/Caddyfile)。
- **CF DNS**: `files.gapul.net` A レコード → `100.64.125.107` (caddy tailnet IP, proxied=false, ttl60)。backrest 等と同形。ワイルドカードは無いので個別レコードが要る。
- tailnet 限定・認証なし(Backrest と同方針)。

## 復元テスト (2026-07-20 実施・全ホスト合格)

各ホストで「復元したファイルの SHA256 がライブと一致」を確認済み。手順:
```sh
# 例 (対象ホストで、そのホストの restic 環境を export した状態):
restic dump --host <host> latest <path> | sha256sum   # ← ライブの sha256sum と一致すれば OK
```
- gdrive 越しの `restic ls`/`stats` は**2分でタイムアウトして誤った欠損判定をしがち**。件数確認は `restic find`(ピンポイント) か pve の `/mnt/restic-view` マウント、または backup run サマリの「processed N files」を使う。macOS に `timeout` は無い(gtimeout)。
