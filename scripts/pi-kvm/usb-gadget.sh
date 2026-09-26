#!/bin/sh
# Compose one USB gadget that is both a network link and a keyboard/mouse.
#
# The Pi used to load the legacy `g_ether` module straight from cmdline, which claims the
# UDC on its own and leaves no room for a second function. configfs lets several functions
# share one gadget, so the same USB-C cable carries ssh *and* the keystrokes we inject into
# whatever machine it is plugged into.
#
# The report descriptors are written by python, not by `printf '\xNN'`: dash's printf does
# not expand \xNN, so the shell version wrote the escapes literally. The result was a 180
# byte "descriptor" that the host rejected with "item fetching failed", leaving the
# keyboard interface unbound while the gadget still looked configured from this side.
set -e
G=/sys/kernel/config/usb_gadget/kvm

modprobe libcomposite
[ -d "$G" ] && exit 0          # already composed (service restarted, not rebooted)

mkdir -p "$G"
cd "$G"
echo 0x1d6b > idVendor         # Linux Foundation
echo 0x0104 > idProduct        # Multifunction Composite Gadget
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB

mkdir -p strings/0x409
echo "0123456789" > strings/0x409/serialnumber
echo "gapul"      > strings/0x409/manufacturer
echo "Pi KVM"     > strings/0x409/product

mkdir -p configs/c.1/strings/0x409
echo "ecm + hid" > configs/c.1/strings/0x409/configuration
echo 0xa0        > configs/c.1/bmAttributes   # bus powered, remote wakeup
echo 250         > configs/c.1/MaxPower

# --- network (ECM: macOS and Linux both bind it without a driver) ---
mkdir -p functions/ecm.usb0
echo "52:d0:5d:33:6e:7a" > functions/ecm.usb0/host_addr
echo "52:d0:5d:33:6e:7b" > functions/ecm.usb0/dev_addr
ln -sf functions/ecm.usb0 configs/c.1/

# --- keyboard (boot protocol, 8-byte reports) ---
mkdir -p functions/hid.kbd
echo 1 > functions/hid.kbd/protocol
echo 1 > functions/hid.kbd/subclass
echo 8 > functions/hid.kbd/report_length
python3 -c 'import sys; sys.stdout.buffer.write(bytes([
  0x05,0x01, 0x09,0x06, 0xa1,0x01,
  0x05,0x07, 0x19,0xe0, 0x29,0xe7, 0x15,0x00, 0x25,0x01,
  0x75,0x01, 0x95,0x08, 0x81,0x02,
  0x95,0x01, 0x75,0x08, 0x81,0x03,
  0x95,0x06, 0x75,0x08, 0x15,0x00, 0x25,0x65,
  0x05,0x07, 0x19,0x00, 0x29,0x65, 0x81,0x00,
  0xc0]))' > functions/hid.kbd/report_desc
ln -sf functions/hid.kbd configs/c.1/

# --- mouse (relative, 3 buttons) ---
mkdir -p functions/hid.mouse
echo 2 > functions/hid.mouse/protocol
echo 1 > functions/hid.mouse/subclass
echo 4 > functions/hid.mouse/report_length
python3 -c 'import sys; sys.stdout.buffer.write(bytes([
  0x05,0x01, 0x09,0x02, 0xa1,0x01, 0x09,0x01, 0xa1,0x00,
  0x05,0x09, 0x19,0x01, 0x29,0x03, 0x15,0x00, 0x25,0x01,
  0x95,0x03, 0x75,0x01, 0x81,0x02,
  0x95,0x01, 0x75,0x05, 0x81,0x03,
  0x05,0x01, 0x09,0x30, 0x09,0x31, 0x09,0x38,
  0x15,0x81, 0x25,0x7f, 0x75,0x08, 0x95,0x03, 0x81,0x06,
  0xc0, 0xc0]))' > functions/hid.mouse/report_desc
ln -sf functions/hid.mouse configs/c.1/

ls /sys/class/udc > UDC

# The host side keeps the address it has always had, so nothing downstream changes.
ip addr add 10.55.0.1/24 dev usb0 2>/dev/null || true
ip link set usb0 up
