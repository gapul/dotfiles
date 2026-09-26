# Pi KVM

Turns a Raspberry Pi 4 into a keyboard, mouse and network link for whatever machine its
USB-C port is plugged into. Paired with an HDMI capture card on the mac, it gives remote
control of a machine that has no working ssh — including at the BIOS screen, where a USB
HID keyboard is initialised by the firmware during POST.

The Pi is `rpi4-kvm` on the tailnet. These files live in `/usr/local/sbin`,
`/usr/local/bin` and `/etc/systemd/system` on it; Raspberry Pi OS is not managed by this
flake, so they are kept here as the source of truth and copied over by hand.

## Install

```sh
scp scripts/pi-kvm/usb-gadget.sh      pi@rpi4-kvm:/tmp/
scp scripts/pi-kvm/usb-gadget.service pi@rpi4-kvm:/tmp/
scp scripts/pi-kvm/hidsend            pi@rpi4-kvm:/tmp/
ssh pi@rpi4-kvm '
  sudo install -m755 /tmp/usb-gadget.sh      /usr/local/sbin/usb-gadget.sh
  sudo install -m644 /tmp/usb-gadget.service /etc/systemd/system/usb-gadget.service
  sudo install -m755 /tmp/hidsend            /usr/local/bin/hidsend
  sudo systemctl daemon-reload && sudo systemctl enable --now usb-gadget.service
'
```

`/boot/firmware/cmdline.txt` must load dwc2 *without* a legacy gadget module — that is,
`modules-load=dwc2` and not `modules-load=dwc2,g_ether`. A legacy module claims the UDC on
its own and leaves no room for the composite gadget. `/boot/firmware` mounts read-only, so
remount it rw before editing.

## Use

```sh
ssh rpi4-kvm hidsend "some text" @enter
ssh rpi4-kvm hidsend @super+2          # modifiers: ctrl shift alt super
ssh rpi4-kvm hidsend @f10 @ctrl+alt+del
```

Plain arguments are typed literally; arguments starting with `@` are key names. The layout
is assumed to be US, because that is what firmware and installers assume and the Pi cannot
see the keycaps of the machine it is driving.

## Traps

**Write the report descriptors as binary.** `printf '\xNN'` in dash does not expand the
escapes, so the shell version wrote them as four literal characters each. The keyboard
descriptor came out 180 bytes instead of 45 and the host rejected it with `item fetching
failed at offset 178/180` / `probe with driver hid-generic failed with error -22`. From the
Pi's side nothing looked wrong: the UDC still read `configured`. The only visible symptom
was that writes to `/dev/hidg0` blocked forever and `/dev/input/by-id` on the host showed
the mouse but no keyboard.

**Check the host, not the gadget.** `cat /sys/class/udc/*/state` says `configured` as soon
as any host has enumerated the device, whether or not it bound the HID interfaces. The
answer is on the other side: `ls /dev/input/by-id/ | grep -i kvm` should list an
`-event-kbd`, and `dmesg` should say `USB HID v1.01 Keyboard`.

**A blocking write means nobody is polling.** Writes to `/dev/hidg0` block until the host
polls the interrupt IN endpoint. Wrap test writes in `timeout` so a broken setup fails in
seconds rather than hanging the session.

**Device nodes come back root-owned.** Re-creating the gadget re-creates `/dev/hidg*` with
mode 600 root:root. `/etc/udev/rules.d/99-hidg.rules` handles new ones, but after a manual
rebuild the nodes need `chgrp pi` + `chmod 660` again.

**Do not leave it plugged into the mac.** In HID mode the Pi is a keyboard for whatever it
is attached to, so keystrokes meant for the target land on the mac instead. The ECM
function is what keeps the Pi reachable while it is plugged in somewhere else — though it
is also on ethernet, which is the path that actually survives the swap.
