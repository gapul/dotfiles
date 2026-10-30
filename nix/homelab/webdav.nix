# WebDAV for the Firefox extensions that cannot be configured by policy (webdav.gapul.net).
# Violentmonkey, Stylus and uBlacklist read no managed storage, so their scripts, styles and
# subscriptions live only inside each browser profile. All three can sync to WebDAV, so this
# gives them one home that the Mac and the NixOS laptop share. Header Editor can back up here
# by hand as well. The list of what is installed is in modules/home/firefox.nix.
#
# One user, basic auth over the tailnet name (Caddy terminates TLS). Authelia is not in front:
# extensions cannot follow an SSO redirect. A password is needed anyway, because whatever is
# stored here runs inside the browser on every page it matches.
#
# The data is a handful of small JSON files under /var/lib/webdav, which the restic job picks
# up with the rest of /var/lib.
{
  services.webdav = {
    enable = true;
    # WEBDAV_USERNAME and WEBDAV_PASSWORD (secrets.nix: webdav.env).
    environmentFile = "/var/lib/secrets/webdav.env";
    settings = {
      address = "127.0.0.1";
      port = 8115;
      behindProxy = true;
      directory = "/var/lib/webdav";
      permissions = "CRUD";
      users = [
        {
          username = "{env}WEBDAV_USERNAME";
          password = "{env}WEBDAV_PASSWORD";
        }
      ];
    };
  };

  systemd.tmpfiles.rules = [ "d /var/lib/webdav 0750 webdav webdav -" ];
}
