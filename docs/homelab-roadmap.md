# Homelab ロードマップ & サービス移行調査

> **注記(2026-08-09)**: この構成はハイパーバイザ無しの NixOS 1台へ置き換え中。
> 設定の実体は `nix/hosts/homeserver.nix` と `nix/homelab/` に移っている。
> 当日の手順は [HOMESERVER_MIGRATION.md](HOMESERVER_MIGRATION.md)。
> 以下は移行元の記録。

最終更新: 2026-07-05

pve(Proxmox)+ CT101(dockge/Docker)を中心とした自宅ホームラボの、残タスクとサービス移行の検討メモ。
タスク番号は Claude Code のタスクリストと対応。

---

## 0. この記録の背景(2026-07-05 に実施済み)

- **Matrix を頂点ドメインで公開**: server_name を `matrix.gapul.net` → `gapul.net` に作り直し、Conduit を federation 有効化。
  既存 CF Tunnel "homelab-pi" を再利用して `matrix.gapul.net` を公開、`gapul.net` の well-known 委任は Caddy が配信。
  federationtester = OK。アカウント `@gapul:gapul.net` 作成・登録ロック済み。**これが自宅初のインターネット公開 ingress。**
  (詳細は memory: matrix-federation-gapul)
- **dash.gapul.net(homepage)をリッチ化**: docker 統計・Proxmox ウィジェット(読み取り専用トークン)・
  siteMonitor・Glances(実ホスト CPU/RAM/温度)・天気・テーマ。表示は英語化。

---

## 1. 残タスク(ロードマップ)

### A. Matrix ブリッジ
- **#7 discord/telegram のログイン** — appservice 側(domain 修正・Conduit へ register・再接続)は完了済み。
  残りはユーザー作業: Element で `@telegrambot:gapul.net` に DM → `login`、
  `@discordbot:gapul.net` に DM → `delete-all-portals`(旧 portal 再生成)or `login-qr`。
- **#8 signal/slack/twitter/meta の新規構築** — 元から未構築でクラッシュループ(`homeserver.address not configured`)。
  bridgev2 形式で config 生成 → gapul.net 向け設定 → `register-appservice` → 各ネットワークにログイン。1個ずつ。
- **#9 Google Messages ブリッジ追加** — `mautrix-gmessages` を compose 追加 → config/register(私)→
  `@gmessagesbot` に DM → スマホの Google メッセージで QR ペアリング(ユーザー)。
  ※ #8 と #9 は手順が同一(bridgev2 新規構築)なのでまとめると効率的。

### B. 運用ハードニング
- **#10 latest イメージの版固定** — 全スタックが `:latest`。今日ブリッジが壊れたのも latest 追従が一因。
  Matrix スタックのダイジェスト取得済:
  - conduit `sha256:4078e80577ccaaf05290a7bb08badc321a5c44a8c8f5f3dce0fb1ae5a0825e64`
  - mautrix/discord `sha256:7716389dfb11dc7a44c8363348a48e91c1c463ded012f0fb08cdf266fcb20246`
  - mautrix/telegram `sha256:17b71cf6d45d7fb4eff3e9ea254613881df6531989031efbfccad12acc1d0782`
- **#11 バックアップの復元テスト** — vzdump+restic→GDrive が「戻せる」か検証。restic check/snapshots、
  試験復元、Vaultwarden・新 Matrix データのカバレッジ、retention 確認。
- **#12 平文シークレットを env/sops 化** — Proxmox トークン(homepage services.yaml)、
  Conduit 登録トークン(compose)、CF_API_TOKEN(cf.env)が平文。最低 .env+perms、理想 sops/docker secrets。
- **#13 Conduit の登録トークン削除** — `ALLOW_REGISTRATION=false` 済みだが compose にトークンが残存(不活性)。掃除。
- **#14 CF トークンを DNS 専用に分割** — Caddy のトークンが DNS 編集 + Tunnel 編集の両方持ち(過剰)。
  Caddy 用は `Zone:DNS:Edit` のみに。※トークン作成は CF ダッシュボード = ユーザー作業。
- **#15 公開 Matrix のハードニング** — `matrix.gapul.net` に CF レート制限/WAF、Conduit 更新の徹底。
  ※ Rules はトークン権限外の見込み → CF ダッシュボード作業。
- **#16 掃除** — `/opt/stacks/matrix` の `cw-data.old-matrixdomain`/`db.old`/`synapse.old`/backup tar、
  homepage の `services.yaml.bak-*` を整理。homepage/glances の docker.sock に socket-proxy を挟むか検討。
- (通知: コンテナ異常 → ntfy は対応済み)

依存関係:
- **#17(脱 Conduit)を決めてから #10(conduit ピン留め)/#13(トークン削除)** の順が無駄がない。
- #14/#15 はどちらも CF ダッシュボードでのユーザー操作が必須。

---

## 2. サービス移行調査(2026、web 調査ベース)

### 2.1 やる価値が高い

#### Conduit 脱却 → Tuwunel(データ保持)or continuwuity(wipe)【#17】
公開 federation 中なのに Conduit は開発停滞。メンテ性=セキュリティなので脱 Conduit 自体は推奨。ただし**移行先の選択が重要**:

- **重要事実**: 素の Conduit の RocksDB は **continuwuity と非互換**。continuwuity へ行くとデータ全消し(wipe)になる。
  (conduwuit の Conduit 互換は一度 one-way になり、その後壊れて撤去された。continuwuity もこれを継承)
- **Tuwunel** は 1.8.0 で **Conduit の RocksDB をその場移行**(rooms/media/knocks 等を保持)。データを残したいならこれが技術的に正解。
  ただし企業/スイス政府系・実質1人開発・多少のプロジェクト間ドラマあり。
- **continuwuity** は非企業コミュニティ後継で活発メンテ(0.5.x)。データ保持は不可だが、
  server_name を `gapul.net` に保てば federation は復活する(=小規模個人サーバなら wipe も許容範囲)。
- どちらも `CONDUIT_*` env 互換。appservice は admin room の `register-appservice` で登録(bridge 再登録が必要)。
- **必ず data dir をバックアップ → コピーで試験してから本番**。continuwuity/tuwunel の DB は Conduit に戻せない。
- 効ort: 低〜中。verdict: **脱 Conduit は推奨。データ保持したいなら Tuwunel、コミュニティ志向で wipe 許容なら continuwuity。**
- Synapse/Dendrite はどちらも Conduit からのクリーン移行不可(同じく wipe)。個人規模には過剰。

出典: continuwuity.org/introduction, forgejo.ellis.link/continuwuation/continuwuity, github.com/matrix-construct/tuwunel,
docs.mau.fi(appservice), pistack.xyz(2026 比較)

#### Uptime Kuma → Gatus【#18】
- Go 単一バイナリ、YAML 宣言、RAM 約 1/3(~10-40MB vs Kuma ~100MB+)。**config-as-code 思想にドンピシャ。**
- HTTP/TCP/ICMP/DNS/TLS/push、条件式(status/latency/JSONPath body/cert 期限)、ステータスページ、メンテ窓、バッジ/API。
- **ntfy はネイティブ対応**(既存の通知経路そのまま)。ストレージは sqlite 推奨。
- 移行: インポータ無し、~20 監視を YAML で再宣言(数時間)。履歴はリセット。
- 補完(競合ではない): **Beszel**(エージェント型リソース監視)、**Healthchecks**(cron/バックアップの死活)。
- 効ort: 低。verdict: **明確な勝ち。** Kuma を1週間並走 → パリティ確認して撤去。

出典: github.com/TwiN/gatus, gatus.io/docs, homelabstarter.com

#### WUD → Diun【#19】
- Go・通知専用・Web UI なし・軽量(~20-40MB、cron で sleep)。**ntfy ネイティブ対応。**
- `watchByDefault=true` で全 ~25 コンテナを一括監視、または `diun.enable=true` ラベルで選択。
- ピン留め運用(#10)と噛み合う「通知のみ・自動更新しない」に最適(Watchtower は自動更新なので別物)。
- WUD の Web UI/REST API/Home Assistant・MQTT を使ってないなら死重。
- 効ort: 低(~20-30分)。verdict: **軽量化の明確な勝ち。**

出典: crazymax.dev/diun, getwud.github.io/wud

#### Obsidian: CouchDB → Syncthing【#20】
- 既に Syncthing 稼働中 → CouchDB(~150-300MB・要バックアップ/更新)を1個丸ごと削減できる。
- **ただし条件付き**。Syncthing は file-level で、同一ノートを複数端末で同時編集すると `.sync-conflict` を吐く。
  `.obsidian/workspace*.json` は端末ごとに書き換わるので `.stignore` 必須(かつ Syncthing は .stignore 自体を同期しない)。
- **モバイルが弱点**: iOS に公式アプリ無し → Möbius Sync(有料)or SyncTrain(無料・要 sandbox 連携)+ iOS のバックグラウンド制限。Android は快適。
- **判断**: デスクトップ中心・常に1端末ずつ・モバイルは Android/読み中心 → **移行して良い**。
  iOS で頻繁に同時編集 → LiveSync 据え置き(リアルタイム + チャンク単位の自動マージ + ネイティブモバイルが強い)。
  無保守が欲しいなら Obsidian 公式 Sync(有料 E2EE)も選択肢。
- 効ort: デスクトップ 30-60分 + モバイル毎の調整(iOS が長い)。**sync ≠ backup、必ず先にバックアップ。**

出典: github.com/vrtmrz/obsidian-livesync, forum.syncthing.net, forum.obsidian.md(Möbius/SyncTrain)

### 2.2 状況次第【#21】

- **RSSHub → rss-bridge**: PHP・Redis 不要・Chromium 不要で軽い。ただし RSSHub は 1000+ ルートに対し
  rss-bridge は ~200 bridges + 汎用 CssSelectorBridge。common な数サイトだけなら rss-bridge、ニッチ多数なら RSSHub 据え置き。
  Miniflux はどちらの feed も食える。移行は feed URL 再作成。
- **ArchiveBox → linkding**: これは**同等ではない**。linkding は軽量ブックマーク管理 + 任意の軽アーカイブ(SingleFile 拡張が本命)。
  ArchiveBox は Chromium で HTML/PDF/screenshot/WARC/動画まで保存する本格アーカイバ。
  実態が「後で読むリンク管理」なら linkding へ(桁違いに軽い)。本気の link-rot 対策アーカイブなら ArchiveBox 据え置き。
  移行は Netscape bookmarks HTML で URL は移せるが、アーカイブ済みコンテンツは移らない(旧 data は静的保管で残す)。

### 2.3 趣味枠(無理に変えなくていい)

- **AdGuard Home → Blocky**: Go・単一 YAML・UI 無し・約半分のメモリ。config-as-code 好きなら。
  ただし AGH の UI/クエリログ/クライアント別制御/DHCP を捨てる。二重化を既に組んでるので優先度低。
- **Homepage → Glance**: Go・YAML・軽量な「朝の briefing」型。ただし homepage の深い per-service ウィジェット(今日作り込んだ)とは用途が違う。両方併用する人も多い。

### 2.4 追加の移行候補(残りサービスを精査)

- **【#22】Proxmox VE → Incus** — MEDIUM-HIGH、**最大の工数**。config-as-code 志向に最も合う唯一の移行。
  Incus(LXD 系)は軽量・完全 OSS・API/CLI first、NixOS+Incus の宣言的ホストと好相性。
  制約: Linux ゲスト限定(Windows VM 不可)・UI 貧弱・小コミュニティ。vzdump+qemu-img で移行可。
  **まず Proxmox 併存で新規 Linux ワークロードから試すのが安全。**
- **Samba に NFS を併用**(置換ではない)— Linux 間限定の共有は NFS が軽く速い。Samba はクロス OS の既定として残す。低工数の最適化。
- **dockge → Komodo**(条件付き MEDIUM)— **複数 Docker ホストに増えたら**。Git 駆動のフリート管理。単一ホストには過剰。

### 2.5 変えなくていい(既に軽量/ベスト)

Vaultwarden(Rust・~50MB、公式 Bitwarden より遥かに軽い)、Miniflux(Go、FreshRSS は横移動)、
ntfy(HTTP first・UnifiedPush)、Navidrome(gonic は軽いが UI を失う・~50MB 差は誤差)、
Jellyfin(FOSS 動画の勝者)、Forgejo(既に GPL/コミュニティ版・Gitea と互換)、
Paperless-ngx(OCR で代替が軒並み劣る・重さは category leader の対価)、dockge(単一ホストでは理想)、
Caddy(config-as-code に最良・自動 TLS)、Home Assistant(2000+ 統合、代替不可)、
Radicale(最軽量、クライアントが困ったら Baïkal/Davis)、Samba(クロス OS の既定として)。

**補助 DB(Redis/Postgres)は per-stack で分離のまま**が正解(共有は SPOF 化・アップグレード結合・バックアップ複雑化を招くだけ、
節約は数 MB で無意味)。

---

## 3. 推奨着手順

1. **足場固め(B の即効くやつ)**: #11 復元テスト → (#17 の方針決定後に)#10 ピン留め・#13 トークン削除。
2. **構成を軽く/堅く(C)**: #17 脱 Conduit(Tuwunel or continuwuity)→ #20 Obsidian を Syncthing 化(サービス 1 個減)→
   #18 Gatus → #19 Diun。
3. **ブリッジ群(A)**: #7 ログイン → #8/#9 新規構築(bridgev2 まとめて)。
4. **CF ダッシュボード作業(ユーザー)**: #14 トークン分割・#15 WAF/レート制限。
5. **長期・大物**: #22 Proxmox → Incus は併存で試してから。

移行は必ず「データ dir バックアップ → コピーで試験 → 本番」。特に Matrix と Vaultwarden。
