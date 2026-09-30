# Kavita — OPDS catalog and web reader for e-books (books.gapul.net).
#
# Audiobookshelf (audiobookshelf.nix) also shelves e-books but doesn't speak OPDS.
# Readest's Audiobookshelf integration only syncs audiobooks, so serving e-books to Readest
# (and other OPDS clients) needs a separate catalog. Kavita scans /srv/books as is and serves
# OPDS via per-user URLs containing an API key. calibre-web requires a Calibre library DB
# and Komga leans toward manga, hence this one.
#
# The library just reads the same /srv/books as Audiobookshelf (excluded from restic).
# State is in /var/lib/kavita (backed up). It has its own login, so no Authelia in front.
{ pkgs, ... }:
let
  tokenKeyFile = "/var/lib/secrets/kavita.token";
in
{
  services.kavita = {
    enable = true;
    inherit tokenKeyFile;
    settings = {
      IpAddresses = "127.0.0.1";
      Port = 8108;
    };
  };

  # JWT signing key. It goes in /var/lib/secrets like the other secrets, but it's a random value
  # shared with no one, so generate it if missing (no extra manual step to put it back after a restore).
  #
  # /var/lib/secrets itself is not created here. The directory mode is owned by the tmpfiles
  # rule in secrets.nix at 0711; an `install -d -m 0700` here reset it to 0700 on every start,
  # and a service that opens secrets as its own user (unified-calendar) stopped with
  # Permission denied (2026-09-27). `install -d` also rewrites the mode of an existing
  # directory.
  systemd.services.kavita-token = {
    description = "Generate the Kavita token key if missing";
    before = [ "kavita.service" ];
    requiredBy = [ "kavita.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ ! -s ${tokenKeyFile} ]; then
        (umask 077; ${pkgs.openssl}/bin/openssl rand -base64 96 | tr -d '\n' > ${tokenKeyFile})
      fi
    '';
  };
}
