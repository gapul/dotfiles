# マイクラのサーバー運用

Realms の代わりに、macmini でマイクラのサーバーを4本動かしている。宣言は
`nix/hosts/macmini.nix` の `minecraftServers`、起動スクリプトは
`configs/macmini/minecraft/`。本書は「触るときにどこを見るか」をまとめたもの。

## 立っているもの

| 名前 | 公開ポート | 版 | 何のため |
|---|---|---|---|
| vanilla | 25565 | Paper 26.2（最新を追う） | 友人と遊ぶ本館。Multiverse で世界を増やせる |
| solo | 25566 | Paper 26.2（最新を追う） | ひとり用。母艦から持ってきた世界2つ |
| fabric | 25568 | Fabric 26.2 | 最新のまま mod で遊ぶ |
| modded | 25567 | NeoForge 1.21.1 | Fabric に来ていない mod（黄昏の森）用 |

外からの入口は playit のトンネルで、転送先は macmini の該当ポート。tailnet 内なら
`100.105.135.49:<ポート>` に直接繋がる。

## 遊んでいない間は動いていない

公開ポートを持っているのは lazymc で、サーバー本体は loopback の +100 番で動く。誰も
居なければ本体はプロセスごと落ちていて、待機コストは lazymc 4本ぶん（約 36MB、CPU 0%）
だけ。接続が来ると起こして繋ぎ、その間クライアントには「起動中」と見える。起動は実測で
4〜5秒、10分無人で停止する。

`freeze_process` は切ってある。既定の凍結（SIGSTOP）は復帰こそ速いが 1.2GB を握った
ままで、4本ぶんとなると 24GB を AI スタックと分け合う機械には重すぎる。

lazymc が突然死ぬ（SIGKILL される）と、その下のサーバーが止まったまま世界のロックを
掴んで残り、次の起動が `already locked` で落ちる。起動スクリプトがロックの持ち主を
片付けてから上がるので、放っておいても直る。

## 増やす・変える

**インスタンスを足す**: `minecraftServers` に1エントリ足すだけ。lazymc・常駐・優先度・
ログ・バックアップは表から生える。ポートは他と重ならない値にする（裏では +100 を使う）。

**世界を足す**（Paper 側）: ゲーム内で `/mv create <名前> normal`。世界は生成物なので
宣言には出てこない。**名前にハイフンを使わない**——26.2 は世界を `minecraft:<名前>` の
キーで持ち、ハイフンはキーとして通らないため、Multiverse の取り込みが失敗する。

**plugin / mod を足す**: `minecraftServers` の `env.PLUGINS` / `env.MODS` に `fetchurl`
で固定したものを並べる。`plugins/` と `mods/` には store への symlink が置かれ、宣言から
外せば次の起動で消える。試すだけなら手で jar を置いてもよく、そちらは消されない。

mod と plugin は自動更新に載せていない。本体に追いつく速度がまちまちで、勝手に上がると
「昨日の世界が開かない」が起きるため。上げるのは人が決める。

## 本体の更新

Paper だけは週次で追う。GitHub Actions の `update-custom-packages` が最新の STABLE
ビルドを見つけて `nix/pkgs/paper-server.nix` を書き換え、同時に `paperMcVersion` /
`paperProtocol`（lazymc が寝ている間に返す版）も動かす。protocol 番号は Paper の API に
無いので minecraft-data から引く。引けなければ据え置いて標準エラーに出す。

macmini は毎朝 5:00 に `git pull` し、post-merge フックが `just rebuild` まで走らせる。

版が上がると世界の変換が走り、変換は一方向。起動スクリプトが変換前の世界を
`<インスタンス>.pre-<旧版>` へ退避してから上げる（直前の1世代だけ残す）。

## バックアップ

毎晩 4:40 に全インスタンスを1本ずつ止めて固め、`/Users/Shared/minecraft-backups` に
7世代残す。5:00 の restic がそのディレクトリごと offsite へ持っていく。

拾うのは world 系のほか `mods/` `plugins/` `config/` `defaultconfigs/` と
`server.properties` / `whitelist.json` / `ops.json`。宣言した jar は store から戻せるが、
手で入れた jar と mod ごとの設定はそこにしか無いため。

戻すときは該当インスタンスを止めて、tar をそのままインスタンスのディレクトリへ展開する。

```bash
sudo launchctl bootout system/org.nixos.minecraft-solo
sudo -u mcsrv tar xzf /Users/Shared/minecraft-backups/solo-<日付>.tar.gz -C /Users/mcsrv/solo
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.minecraft-solo.plist
```

## 古い世界を持ち込む

シングルの世界はそのまま置けば起動時に変換される。ただし DataVersion を持たない世代
（1.9 以前）は 26.2 が受け取らず、「古い版で開いてから」と言って止まる。間に 1.12.2 の
サーバーを挟んで一度読ませてから渡すと通る（1.12.2 は Java 8 が要る。`zulu8` を使う）。

持ち物と座標はワールド内の `playerdata`（26.2 では `players/data`）に入っているので、
フォルダごと移せば引き継がれる。

## 詰まったときに見る場所

- `<インスタンス>/logs/launchd.log` — lazymc の判断（起こした・寝かせた・失敗した）
- `<インスタンス>/logs/latest.log` — サーバー本体
- 外から繋がらない: Application Firewall は許可をバイナリごとに覚えるので、lazymc の
  store path が変わると受信が落ちる。activation で毎回登録し直しているが、疑うならここ。
  loopback からは通るのでサーバー側は正常に見える、という壊れ方をする。
