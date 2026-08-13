# Android

```
android/
├── apps.tsv            # 入れるアプリの宣言 (packageId + どのリポジトリか)
├── apps.sh             # status | install | verify | obtainium
├── os.sh               # 下 2 つを adb で適用 (差分表示 → 適用)
├── os-settings.conf    # settings put する OS 設定
├── os-debloat.txt      # ユーザー 0 から外すプリイン
└── test.sh             # 上 2 つの自己チェック (偽 adb、実機不要)
```

## アプリ

APK を取って `adb install` するところは [fdroidcl](https://github.com/mvdan/fdroidcl)
に任せている。ここが持つのは「何を入れるか」の宣言と差分の判定だけ。

```sh
./apps.sh status      # 宣言 vs 実機。MISSING があれば exit 1
./apps.sh install     # 足りないものを fdroidcl 経由で入れる
./apps.sh verify      # 宣言した packageId がリポジトリに実在するか
./apps.sh obtainium   # 端末の Obtainium に貼る URL リストを出す
```

`status` が `windows/winget/status.ps1` と同じ役割で、`just android-apps` から呼ぶ。
EXTRA (端末に在るが宣言に無い) では落とさない。試しに入れたものは必ず在るし、
消すかどうかは人が決めること。宣言を満たしていないことだけを失敗として扱う。

見に行くリポジトリは F-Droid 公式と IzzyOnDroid の 2 つで、`apps.sh` の
`EXTRA_REPOS` に宣言してある。fdroidcl の設定は母艦の `~/.config` ではなく
専用の場所に置くので、手で fdroidcl を使っていても干渉しない。

Play ストアにしか無いものは `play` と書いておく。一括インストールの手段が
無い (Play に API が無い) ので、`install` は名前を報告するだけ。

**端末側の自動更新は Obtainium が担う。** `apps.sh obtainium` が出す URL リストを
アプリ内の Import/Export → Import from URL List に貼る。URL は packageId から
機械的に決まるので、URL 一覧を別ファイルで持つことはしない。

## OS 設定

```sh
./os.sh --dry-run   # 何が変わるか見る
./os.sh             # 適用
```

USB デバッグを有効にして 1 台だけ繋いだ状態で実行する。現在値と一致する行は
飛ばすので、何度流しても同じ結果になる。

`settings` テーブルに載っている設定しか触れないのが上限で、トグルの多くは
adb からは届かない。それらは手で設定する。

debloat は `pm uninstall -k --user 0` なのでシステムパーティションは無傷で、
`adb shell cmd package install-existing <pkg>` で戻せる。

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
