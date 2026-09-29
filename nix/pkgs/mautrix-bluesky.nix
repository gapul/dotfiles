# mautrix-bluesky: the Go (bridgev2) Bluesky DM bridge. nixpkgs has no package
# for it (checked 2026-09-29), so it is built here in the same shape as
# mautrix-twitter.nix. Drop this file once nixpkgs ships it.
#
# Pinned to a commit rather than a tag: the last tag (v0.2510.0) is a year old
# and the only commits since are dependency updates, which is what keeps the
# mautrix-go side in step with the other bridges.
#
# olm is insecure-flagged; homeserver permits it in homelab/matrix-bridges.nix.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  olm,
}:
buildGoModule (finalAttrs: {
  pname = "mautrix-bluesky";
  version = "0.2510.0-unstable-2026-05-16";

  src = fetchFromGitHub {
    owner = "mautrix";
    repo = "bluesky";
    rev = "0c2076b1b0093ed3c131520f1fd032c3898414ef";
    hash = "sha256-Bp69O3M8MSSC1Dt04bj+0pltEYBLQEh/m9fX5UtGE6w=";
  };

  vendorHash = "sha256-0APWx5d8rDZ32vKwOIVT+TM0Qii874SDQcGk6MIYD6U=";

  # sqlite is cgo.
  env.CGO_ENABLED = "1";

  buildInputs = [ olm ];

  subPackages = [ "cmd/mautrix-bluesky" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Tag=v0.2510.0"
    "-X main.Commit=${finalAttrs.src.rev}"
  ];

  meta = {
    description = "Matrix-Bluesky puppeting bridge";
    homepage = "https://github.com/mautrix/bluesky";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "mautrix-bluesky";
  };
})
