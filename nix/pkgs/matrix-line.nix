# matrix-line: a bridge between Matrix and LINE (mautrix-go bridgev2).
#
# Not in nixpkgs. There is no official mautrix LINE bridge; this is a community
# implementation adopted by Beeper (originally highesttt/matrix-line-messenger). beeper/line
# on GitHub is the current mainline, and the module name in go.mod is still the old one.
#
# It acts as LINE's Chrome extension, so logging in ends the session of the Chrome extension
# version of LINE (and vice versa). Only one of the two can be used at a time.
#
# No tags are published, so it is pinned to a commit.
#
# olm is required by mautrix-go's E2EE. It is marked insecure, so hosts that use it need
# "olm-3.2.16" in nixpkgs.config.permittedInsecurePackages. homeserver already allows it in
# nix/homelab/matrix-bridges.nix, with the reason written there.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  olm,
}:
buildGoModule (finalAttrs: {
  pname = "matrix-line";
  version = "1.2.0-unstable-2026-09-28";

  src = fetchFromGitHub {
    owner = "beeper";
    repo = "line";
    rev = "3b3c06640383e4323074784b7f242e41e9b85d35";
    hash = "sha256-3GiSFzCSKIEN7vqgWXqkGfUY0Bf3f1cD3g6oqpiDwZQ=";
  };

  vendorHash = "sha256-qs0FaqCgKo0a9wrER6G1fAJ/UcOvoZEH2gNvS/hkm2E=";

  # sqlite uses cgo, so it can't be disabled.
  env.CGO_ENABLED = "1";

  buildInputs = [ olm ];

  subPackages = [ "cmd/matrix-line" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Tag=${finalAttrs.version}"
    "-X main.Commit=${finalAttrs.src.rev}"
  ];

  # Some upstream tests assume a real connection to LINE.
  doCheck = false;

  meta = {
    description = "Matrix と LINE を繋ぐブリッジ";
    homepage = "https://github.com/beeper/line";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "matrix-line";
  };
})
