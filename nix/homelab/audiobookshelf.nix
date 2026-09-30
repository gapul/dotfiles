# Audiobookshelf — the audiobook shelf (audiobooks.gapul.net). Ebook serving is kavita.nix.
#
# Two iPhone clients connect: the Audiobookshelf app (self-built, abs- tag in altstore-source)
# and Readest's ABS integration. Both log in with this server's username and password, so
# Authelia is not put in front (same reason as wger).
#
# The actual files are /srv/audiobooks and /srv/books. Like the rest of /srv they are excluded from
# restic (no space spent on things that can be re-bought or re-fetched). Metadata and playback
# positions are in /var/lib/audiobookshelf, which is backed up along with /var/lib.
_: {
  services.audiobookshelf = {
    enable = true;
    host = "127.0.0.1";
    port = 8107;
  };

  # Uploads from the apps are accepted too, so make it owned by the audiobookshelf user.
  systemd.tmpfiles.rules = [
    "d /srv/audiobooks 0755 audiobookshelf audiobookshelf -"
    "d /srv/books 0755 audiobookshelf audiobookshelf -"
  ];
}
