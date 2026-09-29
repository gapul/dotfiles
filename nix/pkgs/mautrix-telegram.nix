# mautrix-telegram: the Go (bridgev2) rewrite of the Telegram bridge.
#
# nixpkgs still ships the legacy Python bridge (0.15.3) under the same name.
# That one predates bridgev2, so it lacks self_sign / msc4190 and does not fit
# the shared bridge helper (homelab/mk-matrix-bridgev2.nix). Drop this file once
# nixpkgs moves to the Go release.
#
# olm is insecure-flagged; homeserver permits it in homelab/matrix-bridges.nix.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  olm,
}:
buildGoModule (finalAttrs: {
  pname = "mautrix-telegram";
  version = "26.09";
  tag = "v0.2609.0";

  src = fetchFromGitHub {
    owner = "mautrix";
    repo = "telegram";
    inherit (finalAttrs) tag;
    hash = "sha256-M8kQap14MRh3tlqOe7JxLkJlsNsJY/COztv0AqvdgF0=";
  };

  vendorHash = "sha256-qW/v/QmhQRF2SAMUNXE2mfVGVEp+DU3gESWVRKHqfGM=";

  # sqlite is cgo.
  env.CGO_ENABLED = "1";

  buildInputs = [ olm ];

  subPackages = [ "cmd/mautrix-telegram" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Tag=${finalAttrs.tag}"
  ];

  meta = {
    description = "Matrix-Telegram puppeting bridge (Go rewrite)";
    homepage = "https://github.com/mautrix/telegram";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "mautrix-telegram";
  };
})
