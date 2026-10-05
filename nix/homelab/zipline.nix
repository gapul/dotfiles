# Screenshot and file sharing (a Gyazo replacement). Zipline v4.
#
# Pingvin (send.gapul.net) hands over a file once and forgets it. This is the other shape:
# "take a screenshot, get a short URL on the clipboard, paste it into a chat", with a history
# of what was shared. The Mac uploads with an API token from the dashboard.
#
# Native module rather than a container: nixpkgs carries Zipline with a hardened unit, and
# its database is one more DB in the native PostgreSQL that atuin and synapse already use
# (database.createLocally). The uploads stay on local disk under /var/lib/private/zipline,
# which restic already covers via /var/lib.
#
# Goes through the tunnel, like send / booking. A shared link is only useful if the
# recipient outside the tailnet can open it, so DNS for i.gapul.net is the tunnel's CNAME.
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
      CORE_DEFAULT_DOMAIN = "i.gapul.net";
      # Already the default; pinned so the public dashboard never grows a sign-up form.
      FEATURES_USER_REGISTRATION = "false";
    };
    # CORE_SECRET (at least 32 characters). See README.md.
    environmentFiles = [ "/var/lib/secrets/zipline.env" ];
  };
}
