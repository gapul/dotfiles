# モバイル (iOS / Android)

スマホは nix が動かない (Android の Termux だけ例外) ので、`windows/` と同じ方針で扱う。
**宣言ファイルを repo に置き、実機との差分を機械に判定させる。**
適用まで自動化できるかはプラットフォーム次第で、できない層は差分を出すところで止める。

```
mobile/
├── android/
│   ├── apps.tsv + apps.sh          # 宣言 vs 実機、F-Droid 系は install まで
│   ├── os-settings.conf            # adb で流すグローバル設定
│   ├── os-apps.tsv + os.sh         # アプリ単位の設定 (権限 / 電池 / 既定ランチャー)
│   ├── launcher-theme.py           # Kvaesitso のテーマを palettes.json から生成
│   └── test.sh                     # 偽 adb での自己チェック
└── ios/
    ├── apps.tsv + sources.tsv      # App Store / AltStore Classic / AltStore PAL
    ├── apps.sh                     # 宣言 vs 実機 (ideviceinstaller)、install は不可
    ├── profiles/serve.sh           # nix が生成した .mobileconfig を配る
    └── test.sh
nix/mobile/ios-profiles.nix         # .mobileconfig の中身 (pkgs.formats.plist)
nix/hosts/droid.nix                 # Termux の中の CLI 環境 (nix-on-droid)
```

## どこまで機械にやらせるか

| 層 | Android | iOS |
|---|---|---|
| アプリ: 宣言 | `android/apps.tsv` | `ios/apps.tsv` |
| アプリ: 実在確認 | `apps.sh verify` (F-Droid 索引 / GitHub API / Play) | `apps.sh verify` (iTunes API / AltStore source) |
| アプリ: 実機との差分 | `apps.sh status` (adb) | `apps.sh status` (ideviceinstaller / USB) |
| アプリ: インストール | `apps.sh install` (F-Droid 系のみ。他は Obtainium / Aurora Store) | **不可**。署名済み ipa が要る |
| OS 設定 (全体) | `os-settings.conf` → `os.sh` | **不可**。`.mobileconfig` で届く範囲だけ |
| OS 設定 (アプリ単位) | `os-apps.tsv` → `os.sh` (権限 / 電池 / 既定ランチャー) | **不可** |
| ランチャー | 既定の指定 + テーマ生成 (レイアウトは不可) | ホーム画面は一切触れない |
| プロファイル生成 | — | `nix build .#ios-profiles` |
| CLI 環境 | `nix/hosts/droid.nix` | 作らない。Blink から母艦へ ssh |

「不可」と書いた欄は API が無い。MDM を建てれば iOS も押し込めるが、端末 2 台に
サーバを建てて監視モードを掛ける値打ちは無いと判断した。

`status` はどちらも MISSING があれば exit 1 で、`windows/winget/status.ps1` と
同じ扱い。EXTRA (実機に在るが宣言に無い) では落とさない。

## 何が自動で、何が手動か

| | いつ走るか |
|---|---|
| 宣言が配布元から消えていないか (`verify`) | **自動**。週次 CI (`.github/workflows/mobile-drift.yml`) |
| スクリプト自身の健全性 (`test.sh`) | **自動**。同 CI + `just mobile-test` |
| 実機との差分 (`status`) | 手動。端末を繋いだときだけ |
| OS 設定の適用 (`os.sh`) | 手動。`just android-os` |
| アプリのインストール | 手動。母艦から `install`、端末で Obtainium / Aurora Store |

端末が常時繋がっていないので、実機に触る側は自動にしていない。無線デバッグを
tailnet 越しに常設すれば定期適用もできるが、繋がっていない間に宣言だけ進んで
「適用したつもり」になる状態を作りたくないので、そこは明示的に叩く形のままにしてある。

自動にしたのは逆に**押した瞬間には気付けないもの**だけ。配布元の改名や削除は
黙って進むので週次で見る (実際 `Catfriend1/syncthing-android` の改名はこれで見つかった)。

## アプリ設定の同期

スマホ側の設定は「ファイルとして同期できるもの」だけ自宅サーバで同期し、
repo は**どのアプリが何の経路で同期されているか**だけを持つ (`apps.tsv` の
同期列と下表)。鍵や DB そのものは入れない。

| アプリ | 経路 | サーバ側の宣言 |
|---|---|---|
| Obsidian | Self-hosted LiveSync (CouchDB) | `nix/homelab/obsidian-couchdb.nix` |
| KeePassium (自ビルド) / KeePassDX | kdbx を Syncthing の SyncHub 経由 | `nix/homelab/syncthing.nix` |
| Bitwarden | Vaultwarden | `nix/homelab/vaultwarden.nix` |
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

- **ホーム画面 / ウィジェット配置** — iOS は手段が無く、Android の Kvaesitso は
  バージョン間で互換の無いバイナリなので、repo に置いても差分が見えない。
  ランチャーはテーマだけ宣言する (`android/launcher-theme.py`)。
- **アプリ本体のバックアップ** — 端末のフルバックアップは iCloud / Seedvault の仕事。
- **iOS の設定トグル** — 監視モードを掛けない限り触れない。手で設定する。
