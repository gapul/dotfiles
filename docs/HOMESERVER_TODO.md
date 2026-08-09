# homeserver 移行 TODO

宣言と検証は済んでいる。ここに残っているのは、判断が要るものと、人の手が要るもの。
当日の手順そのものは [HOMESERVER_MIGRATION.md](HOMESERVER_MIGRATION.md) を見る。

状態: PR #169 で全ワークロードを宣言済み。CI の NixOS VM テストが起動を検証している。
未検証は会社 VPN トンネルのみ(サンドボックスから会社の終端に繋げないため)。

---

## 1. 決めること

先に決めておかないと当日に止まるもの。

- [ ] **退避先をどこにするか**。母艦 Mac(速い・検証しやすい)か Google Drive の
      restic(オフサイト・遅い)。35GB。両方でもよい
- [ ] **実施日**。数時間サービスが止まる。DNS 主系は Pi なので家のインターネットは生きる
- [ ] **tailnet 外の機器が直接叩いているサービスはあるか**。新ホストは tailscale0 しか
      信用しない。心当たりがあるのは Jellyfin(8096)、SMB(139/445)、MQTT(1883)。
      テレビや古い端末から使っているなら、その分だけ firewall を開ける
- [ ] **会社 VPN の接続先をリポジトリに入れてよいか**。いまは勤務先の情報として
      `/var/lib/secrets/mvrx/` に分離してある。気にしないなら nix に取り込めて、
      その分だけ手で置くファイルが減る

## 2. 前日までにやること

- [ ] **平文パスワード2件をローテーション**。archivebox の管理者パスワードと、
      samba の `gapul`。どちらも compose ファイルに平文で入っていた(samba は
      `command:` なので `ps` にも出ていた)
- [ ] **restic の疎通確認**。rclone の Google Drive トークンは1週間ほどで失効し、
      黙って止まる。当日に気づくと退避先が無い
      ```sh
      restic -r rclone:google-drive:restic-backup snapshots | tail -5
      ```
- [ ] **Cloudflare のトークンを用意**(Zone:DNS:Edit)。DNS 付け替えに使う
- [ ] **ISO を用意**。CI の Recovery ISO artifact を落として USB に書く。
      **インストールする世代と同じコミットのもの**を使う
- [ ] **BIOS で USB 起動を確認**。Secure Boot は無効と確認済なので、起動順だけ。
      `ssh pve 'systemctl reboot --firmware-setup'` で直行できる
- [ ] `ha backups new` を取り直す。2026-08-09 の分は母艦にあるが、HA の DB は
      動き続けているので当日の分が要る

## 3. 当日

[HOMESERVER_MIGRATION.md](HOMESERVER_MIGRATION.md) の順に。要約すると、
サービス停止 → 退避 → disko → nixos-install → 秘密を置く → 復元 → 検証。

引き返せなくなる線は `disko --mode destroy` の実行。その前に、退避物が箱の外に
あることを必ずもう一度確認する(vzdump は消えるディスクの上にある)。

## 4. 移行後にやること

サービスは起動するのに、使おうとして初めて壊れているとわかる類。

- [ ] **DNS の付け替え**。`*.gapul.net` 20件超が旧 Caddy の tailnet IP を指している
      ```sh
      export CF_API_TOKEN=...
      scripts/cf-repoint-records.sh --from 100.64.125.107 --to "$(tailscale ip -4)"
      # 一覧を見てから --apply
      ```
- [ ] **A レコードを2件追加**: `esphome.gapul.net`、`nodered.gapul.net`
- [ ] **HA の `trusted_proxies` を `127.0.0.1` に**。直さないと全リクエストが 400
- [ ] **homepage の `services.yaml`**。IP 直書きが19箇所ある
- [ ] **スマホの OwnTracks**。Dawarich の宛先が旧 CT101 の `:3005`
- [ ] **MQTT クライアント**。mosquitto の認証が HA ユーザー依存から独自ユーザーに変わる
- [ ] **Matter デバイスがオンラインに戻るか確認**。戻らなければまずホストの IPv6 を疑う
- [ ] **Syncthing の device ID が変わっていないこと**を確認。変わっていたら身元の復元に失敗
- [ ] **旧スナップショットの掃除**
      ```sh
      restic forget --host pve --tag pve-vzdump --keep-last 1 --prune
      ```
- [ ] **VM105 のディスクイメージを捨てるか判断**。会社トンネルが新環境で一度でも
      上がったら不要
- [ ] **母艦の `~/.ssh/config` に homeserver を追加**(sops 管理側の作業)

## 5. 落ち着いてからやること

急がないが、やると効くもの。

- [ ] **2本目の NVMe を足して ZFS ミラーに**。いまは単騎で冗長ゼロ。
      `zpool attach` で再インストール無しに変換できる。2台目のノードより先に効く
- [ ] **秘密を sops に移す**。ホストの age 鍵ができたら、`/var/lib/secrets` の
      手置きファイルを `secrets/secrets.yaml` へ
- [ ] **イメージをダイジェスト固定 + Renovate**。いまは `:latest` のままで、
      再現性としては中途半端
- [ ] **Raspberry Pi も NixOS に**。AdGuard の主系と副系が1つの定義から生成できる
- [ ] **gatus の死角を埋める**。ntfy とホスト自体が落ちたときは通知が飛ばない。
      Pi から homeserver を見る監視を置くのが素直
- [ ] **Mullvad exit node**(欲しければ)。CT106 は中身が無かったので新規構築。
      ホストの routing table を汚さないよう独自 netns で
- [ ] **deploy-rs か colmena**。ホストが増えてきたら
- [ ] **コンテナのネイティブ化**。forgejo / navidrome / miniflux などはモジュールがある。
      データ移行の手間に見合うと思ったものだけ
