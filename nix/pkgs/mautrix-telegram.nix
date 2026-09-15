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
  version = "26.08";
  tag = "v0.2608.0";

  src = fetchFromGitHub {
    owner = "mautrix";
    repo = "telegram";
    inherit (finalAttrs) tag;
    hash = "sha256-EQ7c98GOaXaMcLF5xJfZ6tV+X9TKjNnd8a3ToJahNsE=";
  };

  vendorHash = "sha256-sh3CejNXhSLp2l4ZnfWwdwxqF+yzCn7/T4EWfVX84m8=";

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
