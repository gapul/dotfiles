#!/system/bin/sh
# AFWall+'s own boot leak script (ukanth/afwall app/src/main/res/raw/afwallstart, GPL-3.0),
# shipped as a module so the declaration holds it instead of the app's "Fix startup data
# leak" toggle. It sets the iptables policies to DROP; AFWall+ resets them once its rules are
# in place, or when the firewall is disabled. So AFWall+ has to have root and the firewall
# enabled before this module is active, or the device boots with no network at all.
# AFWall+ boot leak protection: block all traffic until AFWall+ has applied its rules
# (AFWall+ resets the policies once its rules are in place, or when the firewall is disabled).
#
# This runs at boot (service.d, once netd is up), before the device is unlocked. On devices with
# file-based encryption the app data directory (/data/data/...) is not readable yet, so
# only rely on paths that are: the APK directory (/data/app) to check that AFWall+ is
# still installed, and the system iptables binaries.

export PATH=/system/bin

find_afwall() {
  for pkg in dev.ukanth.ufirewall dev.ukanth.ufirewall.donate; do
    for d in /data/app/"$pkg"-* /data/app/*/"$pkg"-*; do
      if [ -d "$d" ]; then
        echo "$pkg"
        return
      fi
    done
  done
}

pkg=$(find_afwall)
if [ -z "$pkg" ]; then
  log -p i -t afwall "AFWall does not seem to be installed"
  exit
fi

doit() {
  for i in "$@"
  do
    if [ -x "$i" ]
    then
      "$i" -w -P INPUT DROP
      "$i" -w -P OUTPUT DROP
      "$i" -w -P FORWARD DROP
      return
    fi
  done
}

doit /system/bin/iptables /data/data/"$pkg"/app_bin/iptables
doit /system/bin/ip6tables /data/data/"$pkg"/app_bin/ip6tables
log -p i -t afwall "IPv4/6 policy set to DROP"
