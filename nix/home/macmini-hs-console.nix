{
  config,
  pkgs,
  ...
}:
# Out-of-band console for homeserver, for when it no longer answers on SSH
# (2026-10-28: /dev/null was clobbered, sshd reset every connection before the
# banner, and the only way in was the physical console).
#
#   screen   homeserver HDMI -> USB capture card on this Mac ("USB3.0 capture")
#   keyboard rpi4 (Debian, not in this repo) plugged into homeserver's USB with
#            its USB-C in gadget mode; /usr/local/bin/hidsend types into /dev/hidg0
#
# The capture card is read through QuickTime Player, not ffmpeg: ffmpeg's
# avfoundation input hangs on the camera TCC check from agent shells, while
# QuickTime already holds the camera grant. QuickTime is driven over
# `ssh localhost` because the Automation grant then belongs to
# sshd-keygen-wrapper, whose path does not change when t3/claude update
# (same reason as remote-ui, see mac-gui-via-ssh-localhost).
let
  home = config.home.homeDirectory;
  # Tailnet first; LAN as the fallback for when tailscale is what broke.
  piHosts = "100.88.76.97 192.168.116.101";
  piHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBA9kQn7R7pi0I8BuPQ79LyXDZqCKTK0tHhnJrATj4V5";
  knownHosts = pkgs.writeText "rpi4-known-hosts" ''
    100.88.76.97 ${piHostKey}
    192.168.116.101 ${piHostKey}
  '';
  # Placed by hosts/macmini.nix (sops, host-key decryption). The vault cache is
  # local, so unlocking works even while vault.gapul.net (on homeserver) is down.
  bwMasterFile = "${home}/.config/aac/bw-master-password";
  loginItem = "homeserver (SSH)";

  hsConsole = pkgs.writeShellApplication {
    name = "hs-console";
    runtimeInputs = with pkgs; [
      ffmpeg
      jq
    ];
    text = ''
      outdir="${home}/tmp/hs-console"
      mkdir -p "$outdir"

      pi_ssh() {
        local h rc
        for h in ${piHosts}; do
          rc=0
          /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 -o IdentitiesOnly=yes \
            -o IdentityAgent=none -i "${home}/.ssh/id_ed25519" \
            -o UserKnownHostsFile=${knownHosts} -o StrictHostKeyChecking=yes \
            "pi@$h" "$@" || rc=$?
          # 255 is ssh's own failure, so try the next address; anything else came from the remote command.
          [ "$rc" -eq 255 ] || return "$rc"
        done
        echo "hs-console: rpi4 unreachable on ${piHosts}" >&2
        return 255
      }

      # Arguments go through as hidsend arguments: plain text is typed, @key is a key.
      type_keys() {
        local q
        q=$(printf '%q ' "$@")
        pi_ssh "sudo hidsend $q 2>&1 | grep -v -e SyntaxWarning -e UNSHIFTED || true"
      }

      # The secret goes over stdin, never on a command line on either machine.
      type_secret() {
        # shellcheck disable=SC2016 # expanded on the Pi, not here
        pi_ssh 'p=$(cat); [ -n "$p" ] || exit 1; sudo hidsend "$p" @enter 2>/dev/null'
      }

      login_password() {
        local session id
        session=$(bw unlock --raw --passwordfile "${bwMasterFile}")
        id=$(BW_SESSION=$session bw list items --search "${loginItem}" |
          jq -r --arg n "${loginItem}" 'map(select(.name == $n))[0].id')
        BW_SESSION=$session bw get password "$id"
        BW_SESSION=$session bw lock >/dev/null 2>&1 || true
      }

      shot() {
        local out="''${1:-$outdir/last.png}" mov
        /usr/bin/ssh -o BatchMode=yes localhost "/usr/bin/osascript \
          -e 'tell application \"QuickTime Player\"' \
          -e 'close every document saving no' \
          -e 'set d to new movie recording' -e 'delay 1.5' \
          -e 'start d' -e 'delay 1.5' -e 'stop d' -e 'delay 1' \
          -e 'end tell'" >/dev/null
        mov=$(find "${home}/Library/Containers/com.apple.QuickTimePlayerX/Data/Library/Autosave Information" \
          -name '*.mov' -mmin -1 -print 2>/dev/null | head -1)
        if [ -z "$mov" ]; then
          echo "hs-console: no recording; is the capture card plugged in?" >&2
          return 1
        fi
        ffmpeg -hide_banner -loglevel error -y -sseof -0.3 -i "$mov" -frames:v 1 "$out"
        rm -rf "$(dirname "$mov")"
        echo "$out"
      }

      cmd="''${1:-help}"
      shift || true
      case "$cmd" in
        shot) shot "$@" ;;
        type) type_keys "$@" ;;
        run)
          # hs-console run 'systemctl --failed' [seconds-to-wait]
          type_keys "$1" @enter
          sleep "''${2:-3}"
          shot
          ;;
        login)
          # Whatever state the prompt is in (half-typed name, waiting at Password:), one Enter
          # ends it. A failed attempt makes login(1) pause for seconds and drop keys typed
          # meanwhile — the password then lands in the user name field, in clear on the screen.
          # So wait that out, then a second Enter at a fresh prompt, which re-prompts at once.
          type_keys @enter
          sleep 8
          type_keys @enter
          sleep 2
          type_keys gapul @enter
          sleep 1.5
          login_password | type_secret
          sleep 3
          shot
          ;;
        root)
          type_keys "sudo -i" @enter
          sleep 1.5
          login_password | type_secret
          sleep 2
          shot
          ;;
        logout)
          # Root shell, then gapul's: leave nothing logged in on a console anyone at home can touch.
          type_keys "clear; exit" @enter
          sleep 1
          type_keys "clear; exit" @enter
          sleep 2
          shot
          ;;
        reboot)
          if [ "''${1:-}" != --yes ]; then
            echo "hs-console reboot --yes  (sends Ctrl+Alt+Del: a clean reboot, only if the kernel is alive)" >&2
            exit 2
          fi
          type_keys @ctrl+alt+del
          ;;
        pi) pi_ssh "$@" ;;
        *)
          cat >&2 <<'EOF'
      hs-console: homeserver's physical console from macmini
        shot [file.png]        grab the screen (default ~/tmp/hs-console/last.png)
        type ARGS...           type via the Pi; @enter, @ctrl+c, @f2 are keys
        run 'CMD' [secs]       type CMD, Enter, wait, then shot
        login                  log in as gapul (password from Bitwarden "homeserver (SSH)")
        root                   sudo -i with the same password
        logout                 exit the root and gapul shells
        reboot --yes           Ctrl+Alt+Del
        pi [CMD]               ssh to the Pi itself
      EOF
          ;;
      esac
    '';
  };
in
{
  home.packages = [ hsConsole ];
}
