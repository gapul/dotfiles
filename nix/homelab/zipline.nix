# Screenshot and file sharing (a Gyazo replacement). Zipline v4.
#
# Pingvin (send.gapul.net) hands over a file once and forgets it. This is the other shape:
# "take a screenshot, get a short URL on the clipboard, paste it into a chat", with a history
# of what was shared. The Mac uploads with an API token from the dashboard.
#
# Native module rather than a container: nixpkgs carries Zipline with a hardened unit, and
# its database is one more DB in the native PostgreSQL that atuin and synapse already use
# (database.createLocally). R2 settings and the datasource switch live in the encrypted
# zipline.env. Until that file selects s3, uploads stay on local disk under
# /var/lib/private/zipline, which restic already covers via /var/lib. Copy existing objects
# before switching; selecting a datasource does not migrate them (see README.md).
#
# Goes through the tunnel, like send / booking. A shared link is only useful if the
# recipient outside the tailnet can open it, so DNS for snap.gapul.net is the tunnel's CNAME.
# The dashboard is public along with it and relies on Zipline's own login; registration is
# off by default, so the only account is the one created on first visit.
{
  services.zipline = {
    enable = true;
    settings = {
      CORE_PORT = 8114;
      # Behind cloudflared, so the client IP and scheme come from headers.
      CORE_TRUST_PROXY = "true";
      CORE_RETURN_HTTPS_URLS = "true";
      CORE_DEFAULT_DOMAIN = "snap.gapul.net";
      # Already the default; pinned so the public dashboard never grows a sign-up form.
      FEATURES_USER_REGISTRATION = "false";
      # No DATASOURCE_S3_* here: Zipline validates the S3 block as soon as any of its variables
      # is set, even with DATASOURCE_TYPE=local, and refuses to start without bucket and keys.
      # All R2 settings go into zipline.env together with DATASOURCE_TYPE=s3 (see README.md).
    };
    # CORE_SECRET and R2 connection settings. See README.md.
    environmentFiles = [ "/var/lib/secrets/zipline.env" ];
  };
}
