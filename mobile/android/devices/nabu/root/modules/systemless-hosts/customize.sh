#!/system/bin/sh
# Upstream (symbuzzer/systemless-hosts-KernelSU-module) overlays /system/etc from its own
# service.sh. On this device the overlay upperdir would sit on f2fs, which overlayfs rejects.
# Leaving the file to the metamodule does not work either: meta-mm bind-mounts module files
# read-only, and AdAway's root mode needs to write the file. So the module opts out of the
# metamodule (skip_mount) and post-fs-data.sh binds the file read-write itself.
#
# Copy the hosts file currently in effect, so reinstalling keeps AdAway's list instead of
# resetting it to localhost.
mkdir -p "$MODPATH/system/etc"
cat /system/etc/hosts >"$MODPATH/system/etc/hosts"
chmod 644 "$MODPATH/system/etc/hosts"
chcon --reference=/system/etc/hosts "$MODPATH/system/etc/hosts" 2>/dev/null ||
  busybox chcon --reference /system/etc/hosts "$MODPATH/system/etc/hosts"
touch "$MODPATH/skip_mount"
