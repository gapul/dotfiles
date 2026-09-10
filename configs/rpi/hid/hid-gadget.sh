#!/bin/bash
# Raspberry Pi 4 を「本物の USB キーボードとマウス」にする。
#
# macmini には画面もキーボードも繋がっていないので、TCC の許可ダイアログやログイン画面の
# ように SSH から触れないものが出ると詰む。OS から見て本物の HID になっていれば、CGEvent の
# 注入と違って許可の外側なので必ず通る——その最初の一撃のためだけに使う。
#
# 普段は Pi を USB イーサネットのガジェットに戻してある (g_ether)。使うときだけこれを走らせ、
# 終わったら `modprobe g_ether` で戻す。Pi の USB-C が唯一の peripheral ポート。
set -eu

G=/sys/kernel/config/usb_gadget/hid
UDC=$(ls /sys/class/udc | head -1)

# 作り直すときは先に UDC から外す (bind したままだと EBUSY)
if [ -d "$G" ]; then
  echo "" > "$G/UDC" 2>/dev/null || true
  rm -f "$G"/configs/c.1/hid.usb* 2>/dev/null || true
  rmdir "$G"/configs/c.1/strings/0x409 "$G"/configs/c.1 2>/dev/null || true
  rmdir "$G"/functions/hid.usb0 "$G"/functions/hid.usb1 2>/dev/null || true
  rmdir "$G"/strings/0x409 "$G" 2>/dev/null || true
fi

modprobe libcomposite
mkdir -p "$G"
cd "$G"
echo 0x1d6b > idVendor   # Linux Foundation
echo 0x0104 > idProduct  # Multifunction Composite Gadget
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB
mkdir -p strings/0x409
echo "gapul-rpi4" > strings/0x409/serialnumber
echo "gapul"      > strings/0x409/manufacturer
echo "rpi4 HID"   > strings/0x409/product

# キーボード (boot protocol / 8 バイトレポート)
mkdir -p functions/hid.usb0
echo 1 > functions/hid.usb0/protocol
echo 1 > functions/hid.usb0/subclass
echo 8 > functions/hid.usb0/report_length
printf '\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x03\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x03\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0' > functions/hid.usb0/report_desc

# マウス (絶対座標。相対だと「いまカーソルがどこにあるか」を知る必要があり自動化では詰む)
mkdir -p functions/hid.usb1
echo 0 > functions/hid.usb1/protocol
echo 0 > functions/hid.usb1/subclass
echo 6 > functions/hid.usb1/report_length
printf '\x05\x01\x09\x02\xa1\x01\x09\x01\xa1\x00\x05\x09\x19\x01\x29\x03\x15\x00\x25\x01\x95\x03\x75\x01\x81\x02\x95\x01\x75\x05\x81\x03\x05\x01\x09\x30\x09\x31\x16\x00\x00\x26\xff\x7f\x36\x00\x00\x46\xff\x7f\x75\x10\x95\x02\x81\x02\x09\x38\x15\x81\x25\x7f\x75\x08\x95\x01\x81\x06\xc0\xc0' > functions/hid.usb1/report_desc

mkdir -p configs/c.1/strings/0x409
echo "HID" > configs/c.1/strings/0x409/configuration
echo 250   > configs/c.1/MaxPower
ln -s functions/hid.usb0 configs/c.1/ 2>/dev/null || true
ln -s functions/hid.usb1 configs/c.1/ 2>/dev/null || true

echo "$UDC" > UDC
echo "bound to $UDC"
