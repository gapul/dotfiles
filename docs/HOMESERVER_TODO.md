# homeserver 移行の残り

移行そのものは 2026-08-11 に完了した。コンテナ30個とネイティブサービス一式が稼働、
メモリは 9.7GB → 6.3GB、tailnet IP は `100.127.129.31`。当日の手順と実地の知見は
[HOMESERVER_MIGRATION.md](HOMESERVER_MIGRATION.md) にある。

ここに残すのは、移行後に「使おうとして初めて壊れているとわかった」もの。移行前の
判断待ちと当日手順は役目を終えたので落とした。

2026-08-16 に実機を一通り当たり直した結果を反映してある。

---

## 見つけて直したもの (2026-08-16)

記録として残す。どれも「サービスは起動しているのに中身が死んでいる」形で、
gatus からも podman からも健全に見えていた。

- **Home Assistant が 8/11 の起動以降ずっと recovery mode だった**。移行後に
  `trusted_proxies` を `127.0.0.1` へ直したとき、`[127.0.0.1, ::1]` と書いたのが原因。
  YAML のフローシーケンスでは `::1` を引用符なしに置けない。5日間、Matter も自動化も
  MQTT も動いていなかったのに、コンテナは `Up` でヘルスチェックも通っていた。
- **MQTT が HAOS のアドオンを向いたままだった**。接続先が `core-mosquitto`、ユーザーが
  `homeassistant`。mosquitto 側の `ha` は新規ユーザーなので、パスワードを作り直して
  `/var/lib/secrets/mosquitto-ha.password` と Home Assistant の両方に入れ直した。
- **Matter が `use_addon: true` のままだった**。接続先も `ws://core-matter-server:5580/ws`。
  この設定だと Home Assistant が Supervisor のアドオン管理を呼びに行き、
  `KeyError: 'hassio'` で統合ごと落ちる。ここから `backup` → `cloud` → `default_config` と
  連鎖して default_config が丸ごと立たなくなっていた。`ws://127.0.0.1:5580/ws` に変更。
  ファブリック (`/var/lib/matter-server`) は無事なので再ペアリングは不要だった。
- **tailnet のサブネット経路が5日間ずっと未承認だった**。homeserver は 3 本
  (`192.168.116.0/24` / `192.168.1.0/24` / `10.80.1.0/24`) を広告していたのに承認されて
  おらず、さらに移行で消えたはずの `tailscale-router` と `mvrx-relay` が primary を
  握ったままだった。承認より先に死んだノードを消す順でないと、承認してもそちらへ吸われる。
  移行で物理的に無くなった 5 台 (`caddy` / `pve` / `tailscale-router` / `mvrx-relay` /
  `mullvad-exit`) を削除してから 3 本を承認し、母艦から会社の開発機まで直接届くことを
  確認した (`192.168.1.36:22` と `10.80.1.36:22` の両方)。ProxyJump の迂回はもう要らない。
- **homepage が services.yaml を読めていなかった**。中身の無いグループが残っていて
  `null.forEach` を踏み、ダッシュボードにブックマークしか出ていなかった。中身も
  移行で嘘になっていた (削除済みの AdGuard、ネイティブ化して消えたコンテナ名、
  旧 CT101 の IP を向いた glances) ので実機に合わせて書き直した。
- **samba に `gapul` が居なかった**。インストール当日に手で置くはずの
  `sudo smbpasswd -a gapul` が抜けていて、`pdbedit -L` が空だった。共有 `media` は
  匿名で一覧はできるので「見えている = 使える」と誤解しやすい。パスワードを作って
  登録し、認証が通ることと誤ったパスワードが `NT_STATUS_LOGON_FAILURE` で弾かれる
  ことを確認、値は Bitwarden へ。
- **Dawarich が tailnet のアドレスを拒否していた**。`dawarich.env` の
  `APPLICATION_HOSTS` が `localhost,::1,127.0.0.1` のままで、`100.127.129.31:3005` に
  投げると Rails の host authorization が 403 を返す。localhost からしか触っていな
  かったので気付かなかった。スマホの OwnTracks が動き出す前に踏むところだった。
  tailnet と LAN のアドレスを足して、母艦から OwnTracks 形式の POST を実際に通し、
  points が増えることまで確認した。
- **fgc の ntfy 通知は一度も届いていなかった**。`NOTIFY` が
  `ntfy://fgc:<password>@127.0.0.1:8082/games` で、この 127.0.0.1 はコンテナ自身を指す。
  fgc は `podman` ネットワーク、ntfy は `ntfy_default` にいるので名前でも届かない。
  「失敗時に apprise がコマンド全体をログに吐く」= 平文パスワードが見えていたのは、
  毎回失敗していたから。宛先を `host.containers.internal:8082` に直し、認証は
  `games` への write-only トークンに変更(パスワードより漏れたときに切りやすい)。
  apprise から1通通ることを確認済み。

Home Assistant の `.storage` と `/var/lib/hass` は可変状態なのでリポジトリには入らない。
壊れたら `.storage/core.config_entries.bak-claude` と `configuration.yaml.bak-recovery` が
同じディレクトリにある。

## 残っているもの

- [ ] **Dawarich のスマホ側**。サーバ側は済み(ログインは `gapul@homeserver.local`、
      API キー発行済み、`APPLICATION_HOSTS` 修正済み)。残りは iPhone の OwnTracks を
      `http://100.127.129.31:3005/api/v1/owntracks/points?api_key=…` に向けるところ。
      家の外でも記録するならスマホの Tailscale が常時オンである必要がある
- [ ] **ブリッジの部屋が旧 server_name のまま**。discord の portal は 18 室が
      `!…:matrix.gapul.net` で、join が 404 になる。7月のドメイン変更の取りこぼしで、
      移行とは無関係。直すなら portal を作り直すことになるので判断が要る。telegram 側は
      `No user logins found` でそもそもログインが無い
- [ ] **HAOS と旧ホスト由来のゴミ**。消すかどうかの判断待ち。`core.entity_registry` に
      `platform: hassio` のエンティティが 63 件残っていて、これは永久に unavailable の
      まま。`/var/lib/homelab` にも廃止したスタックの残骸ディレクトリが合計 17MB ある
      (backrest 785K / uptime-kuma 649K / adguard-secondary 16M / adguardhome-sync /
      wud / stirling-pdf.bak)。容量としては無視できるので、消す動機は見通しの良さだけ

## 落ち着いてからやること

急がないが、やると効くもの。

- [ ] **2本目の NVMe を足して ZFS ミラーに**。いまは単騎で冗長ゼロ (`rpool` 472G、使用 5%)。
      `zpool attach` で再インストール無しに変換できる。2台目のノードより先に効く
- [ ] **秘密を sops に移す**。ホストの age 鍵ができたら、`/var/lib/secrets` の
      手置きファイルを `secrets/secrets.yaml` へ。restic の ntfy 通知もこれ待ち
- [ ] **イメージをダイジェスト固定 + Renovate**。いまは `:latest` のままで、
      再現性としては中途半端
- [ ] **Raspberry Pi も NixOS に**。AdGuard の主系と副系が1つの定義から生成できる
- [ ] **gatus の死角を埋める**。ntfy とホスト自体が落ちたときは通知が飛ばない。
      Pi から homeserver を見る監視を置くのが素直。今回の recovery mode のように
      「HTTP 200 は返るが中身が死んでいる」も抜けるので、そこも考える価値がある
- [ ] **Mullvad exit node**(欲しければ)。CT106 は中身が無かったので新規構築。
      ホストの routing table を汚さないよう独自 netns で
- [ ] **deploy-rs か colmena**。ホストが増えてきたら
- [ ] **コンテナのネイティブ化**。forgejo / navidrome / miniflux などはモジュールがある。
      データ移行の手間に見合うと思ったものだけ。Conduit は 2026-08-11 に移行済み
      (`services.matrix-conduit`)。ブリッジは見送った理由を `nix/homelab/matrix.nix` の
      冒頭に書いてある
- [ ] **attic を `services.atticd` へ**。postgres の移行が絡むので単独でやる
