# macmini を遠隔から操作する

macmini は画面もキーボードも繋がっていない。それでも Tailscale 越しの SSH だけで
GUI まで触れるようにしてある。宣言できる部分は `nix/hosts/macmini.nix` に入っているが、
**TCC の許可とスクリーンロックの無効化は宣言できない**ので、その手順をここに残す。

## できること

```bash
# 画面を撮る
ssh macmini 'screencapture -x /tmp/s.png' && scp macmini:/tmp/s.png .

# キーを送る (key code 53 = Escape)
ssh macmini 'osascript -e "tell application \"System Events\" to key code 53"'

# 文字を打つ
ssh macmini 'osascript -e "tell application \"System Events\" to keystroke \"hello\""'

# 座標をクリックする
ssh macmini 'osascript -e "tell application \"System Events\" to click at {960, 540}"'

# ボタンを名前で押す (座標より壊れにくい)
ssh macmini 'osascript -e "tell application \"System Events\" to tell process \"System Settings\" to click button \"Allow\" of window 1"'

# 設定画面を直接開く
ssh macmini 'open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"'
```

## 宣言できないもの

### TCC (アクセシビリティ / 画面収録)

許可の実体は SIP に守られた `TCC.db` にあり、MDM 無しで外から書く方法は無い。GUI で
入れるしかなく、その GUI を触るには許可が要る、という循環になっている。**この循環は
最初に一度だけ、外から物理的にキーボードを挿して破る**（下の「詰んだときの入り口」）。

登録してあるのは `/usr/libexec/sshd-keygen-wrapper` の2つ。SSH セッションから起動した
プロセスは、これを責任者として TCC に問い合わせるため。

1. `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`
2. `+` を押す（ここで管理者認証が出る）
3. ファイル選択で `cmd+shift+G` → `/usr/libexec/sshd-keygen-wrapper` → 開く
4. 同じことを `?Privacy_ScreenCapture` でもやる

`screencapture` が `could not create image from display` を返すなら画面収録が、
`osascript is not allowed to send keystrokes` なら アクセシビリティが外れている。

### スクリーンロック

`sysadminctl -screenLock off` にはアカウントのパスワードが要るので宣言できない。

```bash
ssh -t macmini 'sysadminctl -screenLock off -password -'   # 状態は -screenLock status
```

ロックがかかると、解除にはパスワードを打てる人間が要る。ディスプレイスリープと
スクリーンセーバは activation script で止めてあるので、通常はロック画面に落ちない。

## 詰んだときの入り口

SSH が死んでいる、あるいは TCC を一から入れ直す場合。macmini には画面もキーボードも
無いので、**Raspberry Pi を USB キーボードとして挿す**。Pi 4 の USB-C は peripheral
モードで、`configfs` から HID ガジェット（キーボードとマウス）を作ると、macOS からは
本物の USB 入力装置に見える。CGEvent の注入と違って TCC の外側なので、ログイン画面でも
許可ダイアログでも通る。

画面は macmini の HDMI を母艦の USB キャプチャに入れて見る。

```bash
ffmpeg -f avfoundation -framerate 30 -i "USB3.0 capture" -frames:v 20 -update 1 -y s.png
```

デバイス番号は挿し直すたびに変わるので、番号ではなく名前で指定する。

Pi 側の HID ガジェットの作り方は `configs/rpi/hid/` にある。普段は使わないので、Pi は
USB イーサネットのガジェット構成に戻してある。

## 画面共有について

macOS 標準の画面共有 (5900) は有効で、母艦から `vnc://macmini` で普通に使える。ただし
**VNC のレガシー認証（専用パスワード）は使わない**。その経路で繋ぐと macOS はコンソールの
セッションではなく別の仮想セッションを開くので、画面は真っ黒で入力も届かない。コンソールを
見るにはアカウントの資格情報での認証が要る。

Sunshine (Moonlight で繋ぐ低遅延の配信) も入れてあるが、nixpkgs の macOS ビルドは
`libx264` しか作らず起動時にエンコーダで失敗する。ディスプレイの検出までは通っているので、
直すなら VideoToolbox を有効にしたビルドが要る。
