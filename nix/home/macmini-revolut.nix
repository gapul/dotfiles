{ config, pkgs, ... }:
# Fetches the Revolut account (transactions + balances) for the household ledger and hands
# the JSON to homeserver, where homelab/ledger.nix renders it into the Beancount book.
#
# Why this runs here and not on homeserver with the rest of the ledger: Revolut has no API
# for personal accounts, and app.revolut.com sits behind Cloudflare's bot check, which 403s
# headless browsers and plain HTTP clients at the page itself. personal-tools/revolut drives
# a *headed* Helium (dedicated profile, --use-mock-keychain) over CDP and calls the web
# app's internal API from inside the page. That needs a Mac with a GUI session, which is
# this always-on one. Nobody watches its screen, so the window is harmless.
#
# Login is by hand (phone number + approval in the Revolut app): run `revolut_web.py login`
# on the main Mac and rsync ~/.local/share/revolut/browser-profile here. When the session
# expires the dump exits 2 and this agent says so on ntfy; how long a session lasts is still
# being measured.
let
  home = config.home.homeDirectory;
  tools = "${home}/Developer/github.com/gapul/personal-tools";
  profile = "${home}/.local/share/revolut/browser-profile";
  homeserver = "100.127.129.31"; # tailnet; MagicDNS is off here (blocky)
  ntfyUrlFile = "${home}/.config/ntfy/url";
  ntfyTokenFile = "${home}/.config/ntfy/token";

  dump = pkgs.writeShellScript "revolut-dump" ''
    set -u
    [ -d "${profile}" ] || exit 0 # never logged in on this machine; nothing to do yet
    notify() {
      [ -r "${ntfyUrlFile}" ] && [ -r "${ntfyTokenFile}" ] || return 0
      /usr/bin/curl -fsS -m 15 -H "Authorization: Bearer $(cat "${ntfyTokenFile}")" \
        -H "Title: $1" -H "Tags: ledger" -d "$2" "$(cat "${ntfyUrlFile}")" >/dev/null 2>&1 || true
    }
    # Same "one notification per reason" rule as the ledger jobs on homeserver.
    state="${home}/.local/state/revolut-dump.failed"
    fail() {
      echo "$1" >&2
      if [ "$(cat "$state" 2>/dev/null)" = "$1" ]; then exit 1; fi
      mkdir -p "$(dirname "$state")" && printf '%s' "$1" > "$state"
      notify "Revolut の取り込みに失敗" "$1"
      exit 1
    }
    # https remote: no terminal, so never let git wait on a credential prompt. A stale clone
    # only means an older script, so a failed pull is not fatal.
    GIT_TERMINAL_PROMPT=0 ${pkgs.git}/bin/git -C "${tools}" pull -q --ff-only >/dev/null 2>&1 || true
    out=$(mktemp -t revolut.XXXXXX)
    trap 'rm -f "$out"' EXIT
    if ! err=$(/usr/bin/python3 "${tools}/revolut/revolut_web.py" dump --out "$out" 2>&1 >/dev/null); then
      fail "$err (母艦で revolut_web.py login → rsync -a ~/.local/share/revolut/browser-profile/ macmini:.local/share/revolut/browser-profile/)"
    fi
    ssh="/usr/bin/ssh -i ${home}/.ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20"
    if ! err=$(/usr/bin/scp -q -i ${home}/.ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20 \
          "$out" root@${homeserver}:/var/lib/ledger/incoming/revolut.json.tmp 2>&1 &&
        $ssh root@${homeserver} 'chown ledger:ledger /var/lib/ledger/incoming/revolut.json.tmp && mv /var/lib/ledger/incoming/revolut.json.tmp /var/lib/ledger/incoming/revolut.json' 2>&1); then
      fail "homeserver へ渡せない: $err"
    fi
    rm -f "$state"
  '';
in
{
  launchd.agents.revolut-dump = {
    enable = true;
    config = {
      ProgramArguments = [ "${dump}" ];
      # Before the ledger jobs on homeserver (crypto 06:40, wise 06:50), so Fava shows the
      # same morning. A few minutes of browser time; the path unit there does the rest.
      StartCalendarInterval = [
        {
          Hour = 6;
          Minute = 20;
        }
      ];
      RunAtLoad = false;
      # A GUI app must come up in the Aqua session, which is where user agents run anyway;
      # "Background" would throttle the browser's rendering for no reason.
      ProcessType = "Standard";
      StandardErrorPath = "${home}/Library/Logs/revolut-dump.log";
      StandardOutPath = "${home}/Library/Logs/revolut-dump.log";
    };
  };
}
