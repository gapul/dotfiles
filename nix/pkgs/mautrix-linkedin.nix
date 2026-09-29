# mautrix-linkedin: the Go (bridgev2) LinkedIn bridge. nixpkgs has no package
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
  pname = "mautrix-linkedin";
  version = "26.09";
  tag = "v0.2609.0";

  src = fetchFromGitHub {
    owner = "mautrix";
    repo = "linkedin";
    inherit (finalAttrs) tag;
    hash = "sha256-tGgxlcDq5BfGOmabukfDqZ88lcCLx4/WXHOYHuSxO04=";
  };

  vendorHash = "sha256-6WaikDU5tIMdZdBiAqMPOaiG+mmptTi7GFgPMxB/04E=";

  # sqlite is cgo.
  env.CGO_ENABLED = "1";

  buildInputs = [ olm ];

  subPackages = [ "cmd/mautrix-linkedin" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Tag=${finalAttrs.tag}"
  ];

  meta = {
    description = "Matrix-LinkedIn puppeting bridge";
    homepage = "https://github.com/mautrix/linkedin";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "mautrix-linkedin";
  };
})
