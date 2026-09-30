# Anki sync server. Self-hosted instead of trusting AnkiWeb.
#
# Clients are amgi on iOS (a FOSS fork) and desktop Anki on the workstation. It uses the rslib
# server that ships with Anki itself, so no extra implementation or reverse engineering is
# needed. The sync protocol is plain HTTP, so a caddy vhost like the others is enough.
#
# The password is placed by hand like other secrets (/var/lib/secrets/anki-sync.password).
# Its content is a single plaintext line, which the module reads to create the user.
{
  services.anki-sync-server = {
    enable = true;
    # Only exposed through caddy, so bind to loopback. No direct access over the tailnet either.
    address = "127.0.0.1";
    port = 27701;
    openFirewall = false;
    users = [
      {
        username = "gapul";
        passwordFile = "/var/lib/secrets/anki-sync.password";
      }
    ];
  };
}
