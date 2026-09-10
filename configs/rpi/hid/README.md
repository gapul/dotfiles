# rpi4 を USB キーボードにする

macmini が SSH からも画面共有からも触れなくなったとき（TCC の許可を一から入れる、
ログイン画面から進めない、など）のための最後の入り口。使い方は
[`docs/macmini-remote.md`](../../../docs/macmini-remote.md) を参照。

```bash
scp configs/rpi/hid/* pi@rpi4:/tmp/
ssh pi@rpi4 'sudo modprobe -r g_ether; sudo /tmp/hid-gadget.sh; sudo install -m755 /tmp/hid /usr/local/bin/hid'
ssh pi@rpi4 'sudo hid key esc'
ssh pi@rpi4 'sudo hid type hello'
ssh pi@rpi4 'sudo hid click 16383 16383'   # 絶対座標 0..32767
```

パスワードを打つときは `hid type -` で標準入力から渡す。引数にすると Pi の履歴と
`ps` に残る。

終わったら USB イーサネットのガジェットに戻す。

```bash
ssh pi@rpi4 'sudo sh -c "echo > /sys/kernel/config/usb_gadget/hid/UDC"; sudo modprobe g_ether; sudo rm -f /usr/local/bin/hid'
```
