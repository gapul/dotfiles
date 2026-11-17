# fcitx5-skk from the fork gapul/fcitx5-skk (feature/context-server, on 5.1.11). A server
# dictionary marked context=true is FcitxSkkContextServ instead of libskk's SkkServ: each lookup
# also sends up to 30 characters on either side of the cursor (not from password or sensitive
# fields) to azoo-key-skkserv's request 5, so Zenzai orders the candidates by context
# (社長の|いこう → 意向, 公園へ|いこう → 行こう), and a lost connection is opened again on the next
# lookup instead of staying dead. okuri= picks the readings an entry answers (nasi by default,
# ari, or all): the server handles okuri-ari ones (つかt) poorly from the bare consonant. Only the
# source changes; the build is nixpkgs' own.
{ fcitx5-skk, fetchFromGitHub }:
fcitx5-skk.overrideAttrs {
  version = "5.1.11-context";
  src = fetchFromGitHub {
    owner = "gapul";
    repo = "fcitx5-skk";
    rev = "f224d45385136d2473305451c2aea313c5fdb33f";
    hash = "sha256-X2/KFxaU0tYaq/8HDL3yEmL9cGAZnjGR8odsAAPBkhs=";
  };
}
