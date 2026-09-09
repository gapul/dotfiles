# restic オフサイトバックアップ (共有リポジトリ)

母艦Mac / homeserver / macmini / rpi4 が **同一の暗号化 restic リポジトリ**を共有する:
`rclone:google-drive:restic-backup` (Google Drive 上、rclone 経由)。host 名で相乗り・重複排除。

| ホスト | 対象 | スケジュール | 実装 | 秘密の場所 |
|---|---|---|---|---|
| 母艦 (MacBook-Mini) | Documents/Pictures/Downloads/Movies/Music/Minecraft | 日次 13:00 | home-manager `nix/home/restic-backup.nix` (launchd) | sops-nix |
| homeserver | `/var/lib`、`/srv/dawarich`、`/srv/archivebox`（メディアと attic は対象外） | 日次 03:00 | NixOS `services.restic.backups.homeserver` (`nix/homelab/backup.nix`) | `/var/lib/secrets/` に手動配置 (age 鍵未導入のため) |
| macmini | `~/Developer` + `~/.config` (除外: node_modules/.venv/target/.git/objects/モデルの重み) | 日次 05:00 | home-manager `nix/home/macmini-backup.nix` (launchd) | 手動配置の生ファイル (sops 非導入) |
| rpi4 | `/home/pi` (docker サービスデータ) | 日次 04:30 | `restic-rpi-offsite.sh` + systemd timer | `/root/.config/rclone/rclone.conf` + `/root/.restic.pw` |

- 秘密はどれも `rclone.conf`(GDrive トークン) と restic パスワードで、**このリポジトリには含めない**(sops 経由 or 手動配置)。
- homeserver の Pingvin Share X は配布用キャッシュとして扱う。共有情報・アカウントを含む小さな SQLite DB とその整合性ダンプは保存するが、`data/uploads` の動画と自動生成 ZIP は保存しない。原本をプロジェクト側で保持し、障害時は `hs share create` で共有を作り直す。
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

### macmini / homeserver (宣言済み)
スクリプトも launchd/systemd も nix が生成するので、ここに手順は無い。
秘密だけ手で置く(sops/age を入れていない機械のため)。

- macmini: `nix/home/macmini-backup.nix`。秘密は `~/.config/rclone/rclone.conf` と
  `~/.config/restic/password`、通知用に `~/.config/ntfy/{url,token}`。`just rebuild` で反映。
- homeserver: `nix/homelab/backup.nix`。秘密は `/var/lib/secrets/{rclone.conf,restic.password}`。

2026-08-12 まで macmini は `restic-macmini-offsite.sh` + `local.restic-macmini.plist` の
imperative 構成だった。両方消したので、この README を見て手で置き直さないこと。

## スマホから中身を閲覧 (files.gapul.net)

暗号化リポジトリは Google Drive 上では中身が見えない。プレビューは homeserver 上の
**restic mount (read-only FUSE) + Filestash** で行う。定義は
`nix/homelab/{restic-view,filestash}.nix`。Filestashから同じ画面でGoogle Driveも
扱えるが、バックアップ側は読み取り専用のままにする。

- restic mount は **`--no-lock` 必須**(常駐マウントのロックが日次 prune を塞ぐのを防ぐ)。
- Filestash の待ち受けは **8099**。
- **CF DNS**: `files.gapul.net` の A レコードが個別に要る(ワイルドカードは無い)。
- tailnet 限定で、Caddyの共通認証も通す。

## 復元テスト (2026-07-20 実施・全ホスト合格)

各ホストで「復元したファイルの SHA256 がライブと一致」を確認済み。手順:
```sh
# 例 (対象ホストで、そのホストの restic 環境を export した状態):
restic dump --host <host> latest <path> | sha256sum   # ← ライブの sha256sum と一致すれば OK
```
- gdrive 越しの `restic ls`/`stats` は**2分でタイムアウトして誤った欠損判定をしがち**。件数確認は `restic find`(ピンポイント) か homeserver の `/mnt/restic-view` マウント、または backup run サマリの「processed N files」を使う。macOS に `timeout` は無い(gtimeout)。
