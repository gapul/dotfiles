# iOS

iOS には adb に当たるものが無く、監視モード (Apple Configurator で supervise) を
掛けない限り外から押し込めるものが何も無い。**入れる仕事は自動化できないが、
入っているかの確認と、入れる物の生成はできる**ので、その 2 つを持っている。

```
ios/
├── apps.tsv          # 入れるアプリの宣言 (bundleId + 入手経路 + 同期経路)
├── sources.tsv       # AltStore 系 source の URL (Classic / PAL)
├── apps.sh           # status | verify
├── test.sh           # apps.sh の自己チェック (偽 ideviceinstaller、実機不要)
└── profiles/serve.sh # nix が生成した .mobileconfig を LAN 配信
```

プロファイルの中身は `nix/mobile/ios-profiles.nix`。

## アプリ

```sh
./apps.sh status   # USB 接続した iPhone と宣言の差分。MISSING があれば exit 1
./apps.sh verify   # 宣言した bundleId が経路上に実在するか (3 経路すべて)
```

3 つの経路を使い分けているので、`apps.tsv` の source 列でどれ担当かを宣言する。

| source | 入手 | verify の照会先 |
|---|---|---|
| `appstore` | App Store | iTunes Search API |
| `altstore-classic` | 母艦で再署名して入れる自ビルド | `sources.tsv` の classic な source の JSON |
| `altstore-pal` | AltStore PAL (代替マーケットプレイス) | 同 pal |

`status` は `ideviceinstaller` で実機を照会するので、USB 接続と端末側の
「このコンピュータを信頼」が要る。ネットワーク越しには照会できない。

インストールは自動化できない。App Store も PAL も署名済み ipa を要求するので、
手で入れる。だから `status` は「入れ直しの残りを数える」道具として使う。

**自ビルドは再署名で bundleId が変わる。** App Store 版の `com.keepassium.ios` と
自ビルドの `net.gapul.keepassium` は端末から見て別物なので、宣言する側も
実機に入っている方を書く。`verify` が source の JSON と突き合わせるので、
ここを取り違えると落ちる。

自ビルドの署名配信は [gapul/altstore-source](https://github.com/gapul/altstore-source)
(`sources.tsv` の `gapul-selfbuild`)。ビルド手順は `docs/self-build-software.md`。

## 構成プロファイル

`.mobileconfig` は XML plist でしかないので、payload を nix の attrset で書いて
`pkgs.formats.plist` に流している (`nix/mobile/ios-profiles.nix`)。

```sh
nix build ./nix#ios-profiles   # 生成
./profiles/serve.sh            # LAN に出す (中で nix build もする)
```

同じ LAN の iPhone の Safari から表示された URL を開くと、ダウンロード後に
設定アプリの「プロファイルがダウンロードされました」から入る。Safari 以外の
ブラウザではこの導線に乗らない。

PayloadUUID は名前のハッシュから決定的に導いている。ここが毎回変わると、
更新のたびに別物として端末にプロファイルが積み上がる。

ベンダーが署名済みで配っているものは書かない — NextDNS の DNS プロファイルも
Tailscale の VPN プロファイルも本家が配っていて、そちらの方が信頼済みとして入る。
配布元が無いものだけを宣言する。

| 用途 | どこから |
|---|---|
| 自宅 Radicale の CalDAV/CardDAV | `nix/mobile/ios-profiles.nix` (配布元が無いので自前)。宛先は `hosts/homeserver.nix` の `sites` 表が立てる `dav` の vhost |
| DNS (NextDNS) | `https://apple.nextdns.io/<profile-id>` を Safari で開く |
| 自宅 tailnet | Tailscale アプリ本体が VPN プロファイルを入れる |

## 端末内の CLI

**iOS 上に環境を作らない。** iSH は i386 エミュレーションで遅く、a-Shell は
サンドボックスの都合で普通の Unix にならない。どちらも母艦の設定を持ち込むには
別系統の config を維持する羽目になる。

代わりに [Blink Shell](https://blink.sh) から tailnet 越しに母艦へ入る:

```sh
ssh macmini    # あるいは homeserver
nssh <host>    # rootless nix で nvim/yazi/tmux を自分の設定のまま
```

`nssh` が置いていく設定は `configs/shell/zshrc.remote` で、母艦と共通の部分は
`configs/shell/zshrc.common` を直接読む。つまり iPhone から入っても同じ shell になる。

Blink 自体の設定 (キーマップ、ホスト定義) はアプリ内に閉じていて外に出せないので、
これは宣言管理の外。SSH 鍵は Blink で端末ごとに生成して公開鍵だけ配る
(母艦の鍵を持ち出さない)。
