# iOS

iOS には adb に当たるものが無く、監視モード (Apple Configurator で supervise) を
掛けない限り外から触れるのは構成プロファイル (`.mobileconfig`) だけ。
なので repo が持つのは**目録と、端末に物を届ける手段**に絞ってある。

```
ios/
├── apps.md              # 入れているアプリと入手経路
└── profiles/
    ├── serve.sh         # .mobileconfig を LAN 配信して iPhone の Safari で開く
    └── *.mobileconfig   # ベンダーが配っていないプロファイルだけここに置く
```

## アプリ

[apps.md](apps.md) が目録。App Store / SideStore / TestFlight で入手経路が違い、
どれにも一括インストールの手段が無いので、機種変時に上から入れ直すためのリストとして持つ。

自ビルドの署名配信は [gapul/altstore-source](https://github.com/gapul/altstore-source)
が持っている (SideStore にこの source URL を登録すると自作アプリが更新通知付きで並ぶ)。
ビルド手順そのものは `docs/self-build-software.md`。

## 構成プロファイル

必要なプロファイルの大半はベンダーが署名済みで配っているので、自分で書かない:

| 用途 | 入手元 |
|---|---|
| DNS (NextDNS) | `https://apple.nextdns.io/<profile-id>` を Safari で開く |
| 自宅 tailnet | Tailscale アプリ本体が VPN プロファイルを入れる |
| 証明書 | gapul.net は Let's Encrypt / Cloudflare なので不要 |

ベンダー配布が無いものだけ `profiles/` に `.mobileconfig` を置く。
書くときは `PayloadUUID` を固定値で埋めること。UUID が毎回変わると
再インストールのたびに別プロファイルとして積み上がる。

置いたファイルを実機に入れるには、母艦で:

```sh
profiles/serve.sh
```

同じ LAN の iPhone の Safari から表示された URL を開くと、ダウンロード後に
設定アプリの「プロファイルがダウンロードされました」から入る。
AirDrop でも同じことができるが、こちらは Mac 側が Finder を開かなくて済む。

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
