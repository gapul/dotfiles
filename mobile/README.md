# モバイル (iOS / Android)

スマホは nix が動かない (Android の Termux だけ例外) ので、`windows/` と同じ方針で扱う。
**宣言ファイルを repo に置き、適用は各プラットフォームの純正の仕組みに任せる。**
MDM を建てるほどの規模ではないので、自動化するのは「機械が一括でやれる部分」だけにして、
残りは手順書として書き下す。

```
mobile/
├── android/
│   ├── apps/obtainium-urls.txt   # Obtainium に URL リストで import するアプリ
│   ├── apps/playstore.txt        # Play ストアにしか無いもの (手動)
│   └── adb/apply.sh              # settings.conf / debloat.txt を adb で適用
└── ios/
    ├── apps.md                   # 入れているアプリと入手経路
    └── profiles/serve.sh         # .mobileconfig を LAN 配信して iPhone で開く
```

Android の端末内 CLI (Termux + nix-on-droid) だけは repo の nix 側が持っている:
`nix/hosts/droid.nix`。詳細は [android/README.md](android/README.md)。

## 何をどこで管理するか

| 層 | Android | iOS |
|---|---|---|
| アプリ一覧 | `android/apps/obtainium-urls.txt` (+ Play 分は `playstore.txt`) | `ios/apps.md` (App Store / SideStore / 自ビルド) |
| OS 設定 | `android/adb/settings.conf` を `adb/apply.sh` で流す | `.mobileconfig` (配布物は `ios/profiles/`、多くはベンダー配布のものを使う) |
| CLI 環境 | `nix/hosts/droid.nix` (nix-on-droid) | 端末内には作らない。Blink から tailnet 越しに `ssh macmini` して母艦の環境を使う |
| アプリ設定 | 下の同期表 | 下の同期表 |

## アプリ設定の同期

スマホ側の設定は「ファイルとして同期できるもの」だけ repo の外 (自宅サーバ) で同期し、
repo は**どのアプリが何の経路で同期されているか**だけを持つ。鍵や DB そのものは入れない。

| アプリ | 経路 | サーバ側の宣言 |
|---|---|---|
| Obsidian | Self-hosted LiveSync (CouchDB) | `nix/homelab/obsidian-couchdb.nix` |
| KeePassium (iOS) / KeePassDX (Android) | kdbx を Syncthing の SyncHub 経由 | `nix/homelab/syncthing.nix` |
| Bitwarden | Vaultwarden (自宅) | `nix/homelab/vaultwarden.nix` |
| ntfy | push.gapul.net の topic 購読 | `nix/homelab/ntfy.nix` |
| OwnTracks | 位置ログを Dawarich へ POST | `nix/homelab/dawarich.nix` |
| カレンダー / 連絡先 | CalDAV / CardDAV | `nix/homelab/radicale.nix` |
| RSS | Miniflux (Fever API) | `nix/homelab/miniflux.nix` |
| 音楽 / 動画 / 書類 | Navidrome / Jellyfin / Paperless | 各 `nix/homelab/*.nix` |
| Matrix | Conduit (@gapul:gapul.net) | `nix/homelab/matrix.nix` |

新しい端末を Syncthing に加えるときは、端末の Device ID を
`nix/homelab/syncthing.nix` の `settings.devices` に足して rebuild する。
Web UI で承認するのではなく commit するのがこの repo の作法
(ID は公開鍵なので commit してよい)。

## やらないこと

- **iOS の設定トグルの宣言化** — 監視モード (Apple Configurator で supervise) を掛けない限り
  `.mobileconfig` で触れる範囲は狭く、大半の設定は API が無い。手で設定する。
- **ホーム画面 / ウィジェット配置** — どちらの OS もエクスポート手段が無い。
- **アプリ本体のバックアップ** — 端末のフルバックアップは iCloud / Seedvault の仕事。
