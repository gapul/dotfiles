# homeserver 移行手順(Proxmox → NixOS)

pve(Proxmox 単一ノード)を、ハイパーバイザ無しの NixOS 1台に置き換える当日の手順。
設定側は `nix/hosts/homeserver.nix` と `nix/homelab/` に揃っていて、CI の VM テストが
起動まで確認済み。残りはデータの移送と、手で置く秘密と、一度きりの認証。

段階移行ではないので、サービスごとの切り戻しは無い。pve を消した瞬間に戻り先が消える。

---

## 0. 消える前に理解しておくこと

いまの vzdump のバックアップは `/var/lib/vz/dump` にある。これは置き換える NVMe の
同じディスクの上なので、フォーマットした瞬間に一緒に消える。**箱の外にコピーするまで、
バックアップはバックアップとして機能していない。**

切り戻しが必要になった場合の道は「pve を入れ直して、箱の外に退避したものから戻す」だけ。
数時間かかる。

作業中も家のインターネットは生きる。DNS 主系は Raspberry Pi にあり、この箱には無い。

---

## 1. 前日までにやること

### 1.1 Home Assistant の最後のバックアップ

```sh
ssh -J root@100.101.225.43 root@192.168.116.88   # 使えなければ pve のコンソールから
ha backups new
```

Container 版には組み込みバックアップが無い。Supervisor が作る最後のフルバックアップになる。

### 1.2 平文パスワードのローテーション

以下2つは compose ファイルに平文で入っていた。samba のほうは `command:` にあるので
`ps` にも出る。移行を機に変える。

- archivebox の管理者パスワード
- samba の共有ユーザー `gapul` のパスワード

新しい値は移行後の `/var/lib/secrets/archivebox.env` と `smbpasswd` に入れる。

### 1.3 Cloudflare に A レコードを2つ追加

`esphome.gapul.net` と `nodered.gapul.net`。この2つは HA のアドオン ingress 経由で
開いていたもので、Supervisor が無くなると入口が消えるため独立した vhost にした。
既存と同形(type A / content = Caddy の tailnet IP / proxied=false / ttl=60)。

ワイルドカード証明書は取るが、DNS レコードは1件ずつ必要。

### 1.4 restic の疎通確認

rclone の Google Drive トークンは1週間ほど放置すると失効し、両ホストとも黙って止まる。
当日に気づくと退避先が無い。

```sh
restic -r rclone:google-drive:restic-backup snapshots | tail -5
```

---

## 2. データ退避(35GB)

退避先は Google Drive の restic リポジトリか母艦 Mac。**200GB のマウントは同じ NVMe の上
なので退避先にならない。**

### 2.1 バインドマウントとホスト側ディレクトリ

```sh
ssh pve 'pct exec 101 -- tar -C /opt -czf - stacks' > ~/migration/ct101-stacks.tar.gz
ssh pve 'pct exec 101 -- tar -C /mnt -czf - jellyfin-media' > ~/migration/bulk.tar.gz
```

### 2.2 名前付きボリューム(コピーでは移らない)

docker は `/var/lib/docker/volumes`、podman は `/var/lib/containers/storage/volumes` に
置く。ディレクトリを持っていくのではなく export/import する。名前は新旧で一致している。

```sh
for v in dawarich_dawarich_db_data dawarich_dawarich_public dawarich_dawarich_shared \
         dawarich_dawarich_storage dawarich_dawarich_watched \
         paperless_data paperless_media paperless_redisdata; do
  ssh pve "pct exec 101 -- docker run --rm -v $v:/v alpine tar -C /v -cf - ." > ~/migration/$v.tar
done
```

### 2.3 Home Assistant 一式

```sh
ssh pve 'qm guest exec 100 ...'   # HAOS はシリアルコンソール経由が確実
# /mnt/data/supervisor/homeassistant          69MB  → /var/lib/hass
# /mnt/data/supervisor/apps/data/core_matter_server  8MB → /var/lib/matter-server
# /mnt/data/supervisor/apps/data/a0d7b954_nodered    → /var/lib/node-red
```

Matter の8MBがファブリック。これを失うと全 Matter デバイスを工場出荷リセットして
再ペアリングすることになる。バイト単位で確実に運ぶ。

### 2.4 Syncthing の身元

`/opt/stacks/syncthing/config/config/` にある cert.pem と key.pem。これが device ID の
実体で、再生成すると Mac から見て別のマシンになり、全フォルダを再スキャンする。

### 2.5 退避物の検証

戻せないバックアップを取っても意味がないので、tar を1本 test 展開して中身を確認する。

---

## 3. インストール

### 3.1 ISO

このリポジトリの recovery ISO を使う(CI の Recovery ISO ジョブが毎回ビルドしている)。

```sh
nix build .#recovery-iso   # x86_64-linux が必要。CI の成果物を落としてもよい
```

### 3.2 ディスクを切る

**ここから不可逆。** 実行前に、2章の退避物が箱の外にあることをもう一度確認する。

```sh
sudo disko --mode destroy,format,mount --flake github:gapul/dotfiles?dir=nix#homeserver
```

GPT を切り直し、1GB の ESP と、残り全部の zpool `rpool` を作る。データセットは
root / nix / var-lib / srv / home。srv だけスナップショット対象外。

### 3.3 インストール

```sh
sudo nixos-install --flake github:gapul/dotfiles?dir=nix#homeserver
sudo nixos-enter --root /mnt -c 'passwd gapul'
reboot
```

---

## 4. 秘密と一度きりの認証

すべて root 所有の 0400。sops-nix はこのホストの age 鍵ができるまで使えないので、
最初は手で置く。鍵ができたら `secrets/secrets.yaml` に移す。

| パス | 中身 |
|---|---|
| `/var/lib/secrets/acme-cloudflare.env` | `CF_DNS_API_TOKEN=...`(旧 `/etc/caddy/cf.env` と同じトークン。**変数名が違う**) |
| `/var/lib/secrets/restic.password` | restic リポジトリのパスワード |
| `/var/lib/secrets/rclone.conf` | rclone の設定(google-drive リモート) |
| `/var/lib/secrets/mosquitto-ha.password` | mosquitto_passwd 形式のハッシュ部分のみ |
| `/var/lib/secrets/<stack>.env` × 8 | キーの一覧は `nix/homelab/README.md` |

`<stack>.env` のキー名は旧 `.env` と一致しないものがある。paperless の `PAPERLESS_SECRET`
はコンテナ側では `PAPERLESS_SECRET_KEY`、miniflux はパスワード単体ではなく `DATABASE_URL`
全体が必要。ここを間違えるとサービスは失敗せずに間違った認証情報で起動する。

mosquitto のハッシュ:

```sh
mosquitto_passwd -c /tmp/p ha       # 対話でパスワード入力
cut -d: -f2 /tmp/p > /var/lib/secrets/mosquitto-ha.password
```

一度きりの認証:

```sh
sudo tailscale up --advertise-routes=192.168.116.0/24   # 管理画面でルート承認
sudo smbpasswd -a gapul
# AdGuard の管理者アカウントは https://dns2.gapul.net の初回画面で作る
```

---

## 5. データ復元

**所有者に注意。** 旧環境は全部 root で動く docker コンテナだったが、ネイティブサービスは
それぞれ専用ユーザーで動く。

| 復元先 | 所有者 |
|---|---|
| `/var/lib/homelab/<stack>/` | root(コンテナが root で動くため) |
| `/srv/`(旧 /mnt/jellyfin-media) | root |
| `/var/lib/hass`, `/var/lib/matter-server` | root |
| `/var/lib/syncthing/.config/syncthing/`(cert.pem, key.pem) | `syncthing` |
| `/var/lib/esphome` | `esphome` |
| `/var/lib/node-red` | `node-red` |
| `/var/lib/AdGuardHome` | root(大文字に注意) |

名前付きボリュームの取り込み:

```sh
for v in dawarich_dawarich_db_data ... ; do
  podman volume create $v
  podman volume import $v ~/migration/$v.tar
done
```

Home Assistant の設定を1行直す。`/var/lib/hass/configuration.yaml` の

```yaml
http:
  trusted_proxies: [192.168.116.119]   # 旧 Caddy コンテナ
```

を `127.0.0.1` にする。Caddy が同じホストになったため。直さないと全リクエストが 400 で
弾かれ、痕跡は HA のログにしか出ない。

---

## 6. 検証

```sh
systemctl --failed
journalctl -p err -b --no-pager | tail -40
```

- https://status.gapul.net が緑になるか(gatus が20件を監視している)
- Matter デバイスが Home Assistant でオンラインに戻るか。戻らない場合はまずホストの
  IPv6 を疑う。Matter は Wi-Fi 機器でも IPv6 を要求する
- Syncthing の device ID が `Y72TVZZ-...` のままか。変わっていたら 2.4 の復元に失敗している
- Mac から `restic snapshots` に homeserver タグの新しいスナップショットが出るか
- `dig @<新ホスト> example.com` が引けるか(53番は AdGuard が持つ)
- Jellyfin のハードウェアトランスコードが効くか(`/dev/dri` はメタルなら素直に見える)

コンテナは初回だけイメージ取得で時間がかかる。docker.io は mirror.gcr.io 経由に
宣言済みなのでレート制限は踏まないはず。

データベースを持つスタック(attic / dawarich / miniflux / paperless)は、初回起動で
アプリ側が一度死んで再起動する。compose の health 待ちが systemd の順序依存に変わり、
「起動した」までしか見ないため。`Restart=always` が拾うので放っておいてよい。

---

## 7. 切り戻し

pve は既に存在しないので、戻すなら Proxmox を入れ直して 2章の退避物から復元する。
数時間コース。

現実的な保険は NixOS 側の世代で、設定の問題であれば再起動1回で前の世代を選べる。
ZFS のスナップショットは自動で取られているので、データの問題なら `zfs rollback`。

コンソールという保険は無くなる。pve の Web UI から noVNC で中に入る道が消えるので、
起動しなくなったら物理アクセスになる。BIOS へは `systemctl reboot --firmware-setup`。
