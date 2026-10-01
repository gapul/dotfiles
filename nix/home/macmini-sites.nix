{ config, pkgs, ... }:
# Reads three member sites for the household ledger with a headed browser and hands the
# JSON to homeserver (homelab/ledger.nix renders it): Mobile Suica's SF history (26 weeks,
# 100 entries, so at least monthly), JRE POINT and Bic Camera point balances with expiry.
#
# Same shape as macmini-revolut.nix and for the same reason: none of these has an API, all
# of them keep a browser session alive (Suica through the JRE ID single sign-on) that a
# dedicated Helium profile carries. Login is by hand on the main Mac, then the profile dirs
# under ~/.local/share/<site>/browser-profile are rsync'd here. When a session is gone the
# dump exits 2 and this agent says so on ntfy; the other two sites still get fetched.
let
  home = config.home.homeDirectory;
  tools = "${home}/Developer/github.com/gapul/personal-tools";
  homeserver = "100.127.129.31"; # tailnet; MagicDNS is off here (blocky)
  ntfyUrlFile = "${home}/.config/ntfy/url";
  ntfyTokenFile = "${home}/.config/ntfy/token";
  ssh = "/usr/bin/ssh -i ${home}/.ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20";
  scp = "/usr/bin/scp -q -i ${home}/.ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20";

  dump = pkgs.writeShellScript "sites-dump" ''
    set -u
    notify() {
      [ -r "${ntfyUrlFile}" ] && [ -r "${ntfyTokenFile}" ] || return 0
      /usr/bin/curl -fsS -m 15 -H "Authorization: Bearer $(cat "${ntfyTokenFile}")" \
        -H "Title: $1" -H "Tags: ledger" -d "$2" "$(cat "${ntfyUrlFile}")" >/dev/null 2>&1 || true
    }
    GIT_TERMINAL_PROMPT=0 ${pkgs.git}/bin/git -C "${tools}" pull -q --ff-only >/dev/null 2>&1 || true
    failed=""
    for site in suica jrepoint biccamera; do
      [ -d "${home}/.local/share/$site/browser-profile" ] || continue # never logged in here
      out=$(mktemp -t "$site.XXXXXX")
      if err=$(/usr/bin/python3 "${tools}/$site/''${site}_web.py" dump --out "$out" 2>&1 >/dev/null); then
        ${scp} "$out" "root@${homeserver}:/var/lib/ledger/incoming/$site.json.tmp" &&
          ${ssh} "root@${homeserver}" "chown ledger:ledger /var/lib/ledger/incoming/$site.json.tmp && mv /var/lib/ledger/incoming/$site.json.tmp /var/lib/ledger/incoming/$site.json" ||
          failed="$failed $site(homeserver へ渡せない)"
      else
        # Same "one notification per reason" rule as the ledger jobs: remember the last failure.
        state="${home}/.local/state/sites-dump.$site.failed"
        if [ "$(cat "$state" 2>/dev/null)" != "$err" ]; then
          mkdir -p "$(dirname "$state")" && printf '%s' "$err" > "$state"
          failed="$failed $site($err)"
        fi
        rm -f "$out"
        continue
      fi
      rm -f "$out" "${home}/.local/state/sites-dump.$site.failed"
    done
    [ -z "$failed" ] || notify "会員サイトの取り込みに失敗" "$failed (母艦で <site>_web.py login → プロファイルを rsync)"
  '';
in
{
  launchd.agents.sites-dump = {
    enable = true;
    config = {
      ProgramArguments = [ "${dump}" ];
      # Weekly is enough for 100 entries of Suica history and for point balances; Mobile Suica
      # refuses history between 0:50 and 5:00, so not at night.
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 6;
          Minute = 35;
        }
      ];
      RunAtLoad = false;
      ProcessType = "Standard"; # a GUI app; see macmini-revolut.nix
      StandardErrorPath = "${home}/Library/Logs/sites-dump.log";
      StandardOutPath = "${home}/Library/Logs/sites-dump.log";
    };
  };
}
