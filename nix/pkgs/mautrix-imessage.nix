# mautrix-imessage: a bridge between Matrix and iMessage.
#
# Not in nixpkgs. The other mautrix bridges (discord / signal / meta / telegram) are, but this one
# is macOS-only, so nobody has added it.
#
# Why it needs a Mac: iMessage has no API reachable from outside. This bridge reads
# ~/Library/Messages/chat.db and sends by driving Messages.app. In other words, "a Mac signed in
# to iMessage" is itself the connection, and it cannot be replaced by Linux.
# It is the only bridge that cannot live on the homeserver.
#
# There are no tags, so it is pinned to a commit. Upstream's source of truth is GitLab (mau.dev),
# and GitHub is a mirror, but the mirror can be fetched directly with fetchFromGitHub, so it is
# used here.
#
# Build check (2026-09-01, aarch64-darwin):
#   mautrix-imessage 0.1.0+dev.300ba6d0 (unknown with go1.26.6)
#
# olm is marked insecure, so any host using this needs "olm-3.2.16" in
# nixpkgs.config.permittedInsecurePackages. The homeserver side already allows it in
# nix/homelab/matrix-bridges.nix, which also explains why.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  olm,
}:
buildGoModule (finalAttrs: {
  pname = "mautrix-imessage";
  version = "0-unstable-2026-05-14";

  src = fetchFromGitHub {
    owner = "mautrix";
    repo = "imessage";
    rev = "300ba6d0e5566d1f841d42ee1555779a9b6fa4be";
    hash = "sha256-qKSb4/kktqNHyOKOOLDrAqV+GZ5StU3lGUc3/90CE+c=";
  };

  vendorHash = "sha256-xTzxL4pk6tmWcEhd0bbdwP70hEqNDjB/xahLWY5nRKQ=";

  # Show contact display names in family-name-first order, only for Japanese (CJK) names. Upstream
  # always uses "First Last", so Japanese contacts come out as "結己 川嶋". Match Apple's own
  # formatting.
  patches = [ ./mautrix-imessage-cjk-name-order.patch ];

  # sqlite uses cgo, so this cannot be disabled.
  env.CGO_ENABLED = "1";

  # libheif is not included.
  #
  # With it, HEIC could be converted, so it is actually wanted, but the vendored Go binding
  # (strukturag/libheif v1.19.5) doesn't fit nixpkgs' libheif. The C enum has become a different
  # type and it fails with `cannot use uint32(channel) as _Ctype_heif_channel`. Pinning an old
  # libheif would work, but it goes against the rolling policy and would freeze updates of an
  # image-processing library.
  #
  # Upstream's build.sh also drops the tag when libheif is not found, so this is an expected
  # configuration. The cost is that iMessage photos reach Matrix as .heic. Once the binding catches
  # up, restore tags = [ "libheif" ] and pkg-config.

  # olm is required by mautrix-go's E2EE. It is the same libolm allowed for the other bridges
  # (nix/homelab/matrix-bridges.nix) and carries the deprecation mark. Here too it is only used
  # when E2EE is enabled on the bridge side, which it currently is not.
  # When turning on E2EE, reconsider this together with that file.
  buildInputs = [ olm ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Tag=${finalAttrs.version}"
    "-X main.Commit=${finalAttrs.src.rev}"
  ];

  # Upstream's tests assume a real machine with chat.db and Messages.app.
  doCheck = false;

  meta = {
    description = "Matrix と iMessage を繋ぐブリッジ (macOS 専用)";
    homepage = "https://github.com/mautrix/imessage";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.darwin;
    mainProgram = "mautrix-imessage";
  };
})
