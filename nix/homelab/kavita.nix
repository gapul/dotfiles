# Kavita — 電子書籍の OPDS カタログと Web リーダー (shelf.gapul.net)。
#
# Audiobookshelf (audiobookshelf.nix) は電子書籍も棚に並べるが OPDS を話さない。
# Readest の Audiobookshelf 連携はオーディオブックの同期だけなので、電子書籍を
# Readest (や他の OPDS クライアント) に配るにはカタログが別に要る。Kavita は
# /srv/books をそのまま走査し、ユーザーごとの API キー付き URL で OPDS を出す。
# calibre-web は Calibre のライブラリ DB が前提で、Komga は漫画寄りなのでこちら。
#
# ライブラリは Audiobookshelf と同じ /srv/books を読むだけ (restic 対象外)。
# 状態は /var/lib/kavita (バックアップ対象)。自前ログインを持つので Authelia は挟まない。
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

  # JWT の署名鍵。他の秘密と同じ /var/lib/secrets に置くが、これは誰とも共有しない
  # 乱数なので、無ければ自分で作る (復元後に手で置き直す手順を増やさない)。
  systemd.services.kavita-token = {
    description = "Generate the Kavita token key if missing";
    before = [ "kavita.service" ];
    requiredBy = [ "kavita.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ ! -s ${tokenKeyFile} ]; then
        install -d -m 0700 /var/lib/secrets
        (umask 077; ${pkgs.openssl}/bin/openssl rand -base64 96 | tr -d '\n' > ${tokenKeyFile})
      fi
    '';
  };
}
