# mautrix-slack: newer than nixpkgs (26.07) because the email login flow
# (email -> 6-character code -> pick workspace) only exists from v0.2608.0.
# That flow is what lets the bridge be logged in without pulling xoxc tokens
# and the `d` cookie out of a browser. Same shape as mautrix-twitter.nix; drop
# this file once nixpkgs catches up.
#
# olm is insecure-flagged; homeserver permits it in homelab/matrix-bridges.nix.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  olm,
}:
buildGoModule (finalAttrs: {
  pname = "mautrix-slack";
  version = "26.09.1";
  tag = "v0.2609.1";

  src = fetchFromGitHub {
    owner = "mautrix";
    repo = "slack";
    inherit (finalAttrs) tag;
    hash = "sha256-zaAuRPgrTTdT/nEGN3ULsBqpFPE7iJKFYOB20mXqXUs=";
  };

  vendorHash = "sha256-HgS1dLhMui1Eq4K0KIMajq3cVrNj0Pq4ss6cSRE9V7E=";

  # sqlite is cgo.
  env.CGO_ENABLED = "1";

  buildInputs = [ olm ];

  subPackages = [ "cmd/mautrix-slack" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Tag=${finalAttrs.tag}"
  ];

  meta = {
    description = "Matrix-Slack puppeting bridge";
    homepage = "https://github.com/mautrix/slack";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "mautrix-slack";
  };
})
