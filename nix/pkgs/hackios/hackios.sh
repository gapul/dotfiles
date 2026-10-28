# hackios: iOS 16.5 under QEMU through HackiOS (XNU built from Apple's source, the stock iOS user
# space on top), as a stand-in for the iOS Simulator on Linux. The scripts come from the Nix store;
# everything made from Apple's IPSW lives in the working directory and never in the store.
dir=${HACKIOS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/hackios}
port=${QEMU_SSH_PORT:-2222}
export QEMU_SSH_PORT=$port QEMU_EFI=@efi@ QEMU_VARS=@vars@

usage() {
  cat <<USAGE
usage: hackios COMMAND [ARGS]
  setup              fetch iOS 16.5 from Apple (7.4 GB), the Procursus prefix with OpenSSH, and
                     build the images in $dir (about 12 GB; rerun after a package update)
  run [SECS] [ARGS]  boot in a window (the mouse is a finger; H home, L lock); the session ends
                     after SECS (default 3600). --headless before SECS: no window. ARGS go to QEMU.
                     Home screen after about 7 minutes; the console goes to logs/qemu.log
  push APP.app       sign ad hoc, copy into the running system over ssh, register and open it
  shot [FILE.png]    screenshot (default logs/qemu-screen.png)
  touch STEP...      tap X Y | swipe X0 Y0 X1 Y1 [MS] | key home|lock | wait S (fractions of the screen)
  ssh [CMD]          root shell in the running system
  stop               stop QEMU
USAGE
}

sync_src() {
  mkdir -p "$dir"
  rsync -rl --chmod=u+w @src@/ "$dir"/
}

guest() {
  ssh -i "$dir/ssh/dev_ed25519" -o UserKnownHostsFile="$dir/ssh/known_hosts" \
    -o BatchMode=yes -o ConnectTimeout=10 -p "$port" root@127.0.0.1 "$@"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case "$cmd" in
setup)
  sync_src
  cd "$dir"
  sysimage/fetch.sh
  tools/mk-jb.sh
  mkdir -p ssh && chmod 700 ssh
  [ -f ssh/dev_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -C hackios-dev -f ssh/dev_ed25519
  [ -f ssh/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -N "" -C hackios-host -f ssh/ssh_host_ed25519_key
  cp ssh/dev_ed25519.pub ssh/authorized_keys
  printf '[127.0.0.1]:%s %s\n' "$port" "$(cut -d' ' -f1-2 ssh/ssh_host_ed25519_key.pub)" >ssh/known_hosts
  SYSTEM=1 REST=1 RC_JOBS=rc.jobs.dev userland/build.sh
  ;;
run)
  display=(-display gtk)
  if [ "${1:-}" = --headless ]; then
    display=()
    shift
  fi
  secs=${1:-3600}
  [ $# -gt 0 ] && shift
  sync_src
  cd "$dir"
  mkdir -p logs
  echo "hackios: console in $dir/logs/qemu.log; ssh on 127.0.0.1:$port once the network is up"
  QEMU_NET=1 qemu/run-ios.sh "$secs" "${display[@]}" "$@" >logs/qemu.log 2>&1
  ;;
push)
  app=$(realpath "${1:?usage: hackios push APP.app}")
  name=$(basename "$app")
  read -r exe bundle < <(python3 -c 'import plistlib, sys; d = plistlib.load(open(sys.argv[1], "rb")); print(d["CFBundleExecutable"], d["CFBundleIdentifier"])' "$app/Info.plist")
  # xtool links without LC_CODE_SIGNATURE; the guest's AMFI is a stub but the kernel still wants one
  ldid -S "$app/$exe"
  tar -C "$(dirname "$app")" -cf - "$name" | guest "
    export PATH=/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:\$PATH
    killall -9 '$exe' 2>/dev/null || true
    rm -rf '/var/jb/Applications/$name' && tar -C /var/jb/Applications -xf - || exit 1
    # LaunchServices rebuilds its database while the system is still coming up and forgets what
    # was registered before that, so register and open until the process is really there
    for try in 1 2 3 4 5 6 7 8 9 10; do
      uicache -p '/var/jb/Applications/$name' && uiopen --bundleid '$bundle'
      for wait in 1 2 3 4 5 6; do
        sleep 5
        ps -A | grep -v grep | grep -q '/$name/$exe' && exit 0
      done
      echo 'hackios: not running yet (still booting?), registering again' >&2
    done
    exit 1"
  echo "hackios: $bundle running"
  ;;
shot)
  out=$(realpath -m "${1:-$dir/logs/qemu-screen.png}")
  bash "$dir/qemu/screendump.sh" "$out" >/dev/null
  echo "$out"
  ;;
touch) python3 "$dir/qemu/touch.py" "$@" ;;
ssh) guest "$@" ;;
stop) bash "$dir/qemu/stop.sh" ;;
*)
  usage
  [ -z "$cmd" ] || [ "$cmd" = help ] || exit 1
  ;;
esac
