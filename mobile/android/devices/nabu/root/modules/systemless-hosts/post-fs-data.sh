#!/system/bin/sh
# Bind before zygote starts, so every app sees the module's hosts file. See customize.sh for
# why this is not left to the metamodule.
MODDIR=${0%/*}
mount -o bind "$MODDIR/system/etc/hosts" /system/etc/hosts
