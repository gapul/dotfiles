# Android

```
android/
├── apps.tsv            # 入れるアプリの宣言 (packageId + 経路)
├── apps.sh             # status | install | verify | obtainium
├── os-settings.conf    # settings put するグローバル設定
├── os-apps.tsv         # アプリ単位の OS 側設定 (既定ランチャー / 権限 / 電池)
├── os-debloat.txt      # ユーザー 0 から外すプリイン
├── os.sh               # 上 3 つを adb で適用 (差分表示 → 適用)
├── launcher-theme.py   # Kvaesitso のテーマを palettes.json から生成
└── test.sh             # 上のスクリプトの自己チェック (偽 adb、実機不要)
```

## アプリ

3 つのストアを使い分けているので、`apps.tsv` の source 列でどれ担当かを宣言する。

| source | 配布元 | 母艦から入れる | 端末側で更新 |
|---|---|---|---|
| `fdroid` | F-Droid 公式 | ○ `apps.sh install` | Obtainium / F-Droid |
| `izzy` | IzzyOnDroid | ○ 同上 | Obtainium |
| `github` | GitHub Releases | × | Obtainium |
| `play` | Play ストア | × | Aurora Store |

```sh
./apps.sh status      # 宣言 vs 実機。MISSING があれば exit 1
./apps.sh install     # F-Droid 系を fdroidcl 経由で入れる。残りは経路を報告
./apps.sh verify      # 4 経路すべてに実在するか確かめる
./apps.sh obtainium   # 端末の Obtainium に貼る URL リストを出す
```

APK を取って `adb install` する部分は [fdroidcl](https://github.com/mvdan/fdroidcl)
に任せている。ここが持つのは「何を入れるか」の宣言と差分の判定だけ。

`status` が `windows/winget/status.ps1` と同じ役割で、`just android-apps` から呼ぶ。
EXTRA (端末に在るが宣言に無い) では落とさない。試しに入れたものは必ず在るし、
消すかどうかは人が決めること。宣言を満たしていないことだけを失敗として扱う。

`verify` は F-Droid の索引 / GitHub API / Play のストアページを引いて、
綴り間違いと配布元の移転を捕まえる。実際これで `Catfriend1/syncthing-android` が
`researchxxl/` に改名済みなのが見つかった。GitHub 照会は `gh` があればそちらを使う
(未認証の API は 60 回/時で、宣言が増えると rate limit で落ちる)。

**端末側の自動更新は Obtainium が担う。** `apps.sh obtainium` が出す URL リストを
アプリ内の Import/Export → Import from URL List に貼る。URL は packageId / ref から
機械的に決まるので、URL 一覧を別ファイルで持つことはしない。

いまは `play` 行がゼロなので、**宣言した全アプリがこの 1 回の import で端末側に載る**。
母艦から `install` できない `github` 行も、Obtainium に入れば追跡と更新は同じように効く。
Play にしか無いものが出てきたときだけ手が要るので、GitHub 配布があるなら
`play` ではなく `github` に寄せる (Bitwarden は GitHub Releases に APK があったので移した)。

## OS 設定

```sh
./os.sh --dry-run   # 何が変わるか見る
./os.sh             # 適用
```

USB デバッグを有効にして 1 台だけ繋いだ状態で実行する。現在値と一致する行は
飛ばすので、何度流しても同じ結果になる。

- `os-settings.conf` — `settings` テーブルに載っているグローバル設定。
  トグルの多くはここに無く、adb からは届かないので手で設定する。
- `os-apps.tsv` — アプリ単位。既定ランチャー / 権限の付け外し / AppOps /
  電池最適化の除外。アプリ「内部」の設定 (アカウントや同期先) はどうやっても
  外から触れないので、アプリ自身の同期機能に任せる (`../README.md` の表)。
- `os-debloat.txt` — `pm uninstall -k --user 0` なのでシステムパーティションは
  無傷で、`adb shell cmd package install-existing <pkg>` で戻せる。

## ランチャー (Kvaesitso)

ホーム画面のレイアウトやウィジェット配置は宣言しない。Kvaesitso のバックアップは
バージョン間で互換が保証されないバイナリで、repo に置いても差分が見えないため。

宣言しているのは 2 つ:

- **既定ランチャーであること** — `os-apps.tsv` の `home` 行が
  `cmd package set-home-activity` で設定する。
- **テーマ** — `launcher-theme.py` が `configs/theme/palettes.json` から
  ThemeBundle v2 (JSON) を生成する。母艦・tmux・Windows と同じ SSOT に乗るので、
  rose-pine を差し替えればランチャーも一緒に変わる。light/dark 両方を 1 つの
  テーマに入れてあるので、端末の外観設定に追従する。

```sh
just android-launcher-theme   # 生成して /sdcard/Download/ に push
# 端末で Kvaesitso → 設定 → 外観 → テーマ → インポート
```

## 端末内の CLI (nix-on-droid)

母艦と同じ zsh / git / tmux / CLI ツールが Termux の上に載る。設定の実体は
`nix/hosts/droid.nix` で、`nix/modules/home/` の git / cli / shell / terminal を
そのまま共有している。GUI 前提の component と、flake input のモジュールに依存する
component (nix-index, agent-skills) は読み込まない。

初回は [Termux:Nix](https://f-droid.org/packages/com.termux.nix/) を入れて
(通常の Termux ではなく nix 対応版)、アプリ内で:

```sh
nix-on-droid switch --flake github:gapul/dotfiles?dir=nix#default
```

以降の更新も同じコマンド。CI では `nix run .#ci-nixondroid` (aarch64-linux)
が activation package のビルドだけ通している。
