# A separate browser for affiliate applications: keep the daily Firefox/Helium
# protection in place, while allowing attribution cookies in this profile.
{ pkgs, ... }:
let
  initialPreferences = pkgs.writeText "affiliate-preferences.json" (
    builtins.toJSON {
      profile.block_third_party_cookies = false;
    }
  );
  launcher = pkgs.writeShellApplication {
    name = "chromium-affiliate";
    runtimeInputs = [
      pkgs.jq
      pkgs.util-linux
    ];
    text = ''
      umask 077
      profile="''${XDG_DATA_HOME:-$HOME/.local/share}/chromium-affiliate"
      # Seed only on first use; never overwrite Chromium's running profile state.
      if [ ! -d "$profile" ]; then
        mkdir -p "$profile/Default"
        cp ${initialPreferences} "$profile/Default/Preferences"
        chmod 600 "$profile/Default/Preferences"
      fi
      # Preferences are read at startup. Do not edit an active Chromium profile.
      mkdir -p "$profile"
      exec 9>"$profile/affiliate-launch.lock"
      flock -n 9 || { echo "The application browser is already running." >&2; exit 1; }
      if [ -L "$profile/SingletonLock" ]; then
        owner=$(readlink "$profile/SingletonLock")
        pid="''${owner##*-}"
        if kill -0 "$pid" 2>/dev/null; then
          echo "Close Chromium (申込用) before changing its DNS settings." >&2
          exit 1
        fi
      fi
      preferences="$profile/Default/Preferences"
      temporary=$(mktemp "$preferences.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      jq 'del(.dns_over_https) | .profile.block_third_party_cookies = false' "$preferences" > "$temporary"
      mv "$temporary" "$preferences"
      trap - EXIT
      # Secure DNS is a browser-wide preference stored in Local State, not Preferences.
      local_state="$profile/Local State"
      if [ ! -f "$local_state" ]; then printf '{}\n' > "$local_state"; fi
      temporary=$(mktemp "$local_state.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      jq '.dns_over_https.mode = "secure" | .dns_over_https.templates = "https://cloudflare-dns.com/dns-query"' "$local_state" > "$temporary"
      mv "$temporary" "$local_state"
      trap - EXIT
      exec ${pkgs.chromium}/bin/chromium \
        --user-data-dir="$profile" \
        --disable-extensions \
        --no-first-run \
        "$@"
    '';
  };
in
{
  # Do not use programs.chromium.extraOpts: Helium also reads /etc/chromium/policies.
  # DNS and the VPN route must be prepared separately before starting an application.
  environment.systemPackages = [
    pkgs.chromium
    launcher
    (pkgs.makeDesktopItem {
      name = "chromium-affiliate";
      desktopName = "Chromium (申込用)";
      exec = "${launcher}/bin/chromium-affiliate %U";
      icon = "chromium";
      categories = [
        "Network"
        "WebBrowser"
      ];
      comment = "専用プロファイル・拡張なし。申込前にVPNの経路も確認";
    })
  ];
}
