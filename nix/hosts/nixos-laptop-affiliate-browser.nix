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
    text = ''
      umask 077
      profile="''${XDG_DATA_HOME:-$HOME/.local/share}/chromium-affiliate"
      # Seed only on first use; never overwrite Chromium's running profile state.
      if [ ! -d "$profile" ]; then
        mkdir -p "$profile/Default"
        cp ${initialPreferences} "$profile/Default/Preferences"
        chmod 600 "$profile/Default/Preferences"
      fi
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
