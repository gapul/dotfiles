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
  version = "26.10";
  tag = "v0.2610.0";

  src = fetchFromGitHub {
    owner = "mautrix";
    repo = "telegram";
    inherit (finalAttrs) tag;
    hash = "sha256-2oHtqtpFhNr+v49nMSe33RGDj+MQV2D/+8JX+YYWi+0=";
  };

  vendorHash = "sha256-JbnlJnCtIKC3rpO2mBa7DvEFeWuq9tpvN9H+MoQ5VV0=";

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
