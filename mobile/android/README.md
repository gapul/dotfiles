# Android

nix が届く層 (Termux) と届かない層 (OS 設定 / アプリ) で手段が分かれる。

```
android/
├── apps/obtainium-urls.txt   # Obtainium に URL リストで import
├── apps/playstore.txt        # Play にしか無いもの (手動、機種変時の目録)
└── adb/
    ├── apply.sh              # 下 2 つを adb で流す (差分表示 → 適用)
    ├── test-apply.sh         # apply.sh の自己チェック (偽 adb、実機不要)
    ├── settings.conf         # settings put する OS 設定
    └── debloat.txt           # ユーザー 0 から外すプリイン
```

## 端末内の CLI (nix-on-droid)

母艦と同じ zsh / git / tmux / CLI ツールが Termux の上に載る。設定の実体は
`nix/hosts/droid.nix` で、`nix/modules/home/` の git / cli / shell / terminal を
そのまま共有している。GUI 前提の component と、flake input のモジュールに依存する
component (nix-index, agent-skills) は読み込まない。

初回:

1. [Termux:Nix](https://f-droid.org/packages/com.termux.nix/) を F-Droid から入れる
   (通常の Termux ではなく nix 対応版)
2. アプリ内で:

```sh
nix-on-droid switch --flake github:gapul/dotfiles?dir=nix#default
```

以降の更新も同じコマンド。CI では `nix run .#ci-nixondroid` (aarch64-linux)
が activation package のビルドだけ通している。

## アプリ

[Obtainium](https://github.com/ImranR98/Obtainium) が一次。GitHub Releases と
F-Droid から直接追ってくれるので、Play を経由せずにアプリ一覧を宣言できる。

アプリ内 → 設定 → Import/Export → **Import from URL List** に
`apps/obtainium-urls.txt` の中身を貼る。逆に端末側で足したアプリは
Export した URL リストをこのファイルに書き戻す。

> エクスポートされる JSON (アプリごとの追跡設定込み) ではなく URL リストで持っている。
> JSON はスキーマがバージョンで動く上に人が読めない。追跡設定を細かく詰めたくなったら
> JSON に切り替える。

Play ストアにしか無いものは一括で入れる手段が無いので `apps/playstore.txt` に
名前だけ並べてある。

## OS 設定

```sh
adb/apply.sh --dry-run   # 何が変わるか見る
adb/apply.sh             # 適用
adb/test-apply.sh        # スクリプト自体の自己チェック (実機不要)
```

USB デバッグを有効にして 1 台だけ繋いだ状態で実行する。現在値と一致する行は
飛ばすので、何度流しても同じ結果になる。`adb` は
`nix shell nixpkgs#android-tools` で用意する。

`settings` テーブルに載っている設定しか触れないのが上限で、トグルの多くは
adb からは届かない。それらは手で設定する。

debloat は `pm uninstall -k --user 0` なのでシステムパーティションは無傷で、
`adb shell cmd package install-existing <pkg>` で戻せる。
