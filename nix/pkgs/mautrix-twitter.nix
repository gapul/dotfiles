# mautrix-twitter: the Go (bridgev2) X (Twitter) bridge. nixpkgs has no package
# for it (checked 2026-09-29), so it is built here in the same shape as
# mautrix-telegram.nix. Drop this file once nixpkgs ships it.
#
# olm is insecure-flagged; homeserver permits it in homelab/matrix-bridges.nix.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  olm,
}:
buildGoModule (finalAttrs: {
  pname = "mautrix-twitter";
  version = "26.09";
  tag = "v0.2609.0";

  src = fetchFromGitHub {
    owner = "mautrix";
    repo = "twitter";
    inherit (finalAttrs) tag;
    hash = "sha256-reUzyhigVZM9IqYGHMOTdTT0UTD9oAEJkeqUFvGmGvM=";
  };

  vendorHash = "sha256-tePfW71Rd1krac2+UQK7JhyyKqkyAGyMkXh1knvtZUM=";

  # sqlite is cgo.
  env.CGO_ENABLED = "1";

  buildInputs = [ olm ];

  subPackages = [ "cmd/mautrix-twitter" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Tag=${finalAttrs.tag}"
  ];

  meta = {
    description = "Matrix-X (Twitter) puppeting bridge";
    homepage = "https://github.com/mautrix/twitter";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "mautrix-twitter";
  };
})
