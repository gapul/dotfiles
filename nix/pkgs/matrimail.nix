# matrimail: Matrix <-> email bridge (mautrix-go bridgev2). One email thread is
# one room, delivery is IMAP IDLE, replies and new threads go out over SMTP
# submission (587 STARTTLS) or the Gmail API. Chosen over postmoogle because
# postmoogle is an SMTP *server* that needs port 25 reachable, and the home line
# is behind OP25B (homelab/mail.nix). IMAP to the providers is not blocked.
#
# Not in nixpkgs. Small project (a fork lineage of emaildawg), pinned to a tag.
#
# olm is insecure-flagged; homeserver permits it in homelab/matrix-bridges.nix.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  olm,
}:
buildGoModule (finalAttrs: {
  pname = "matrimail";
  version = "1.9.3";

  src = fetchFromGitHub {
    owner = "moiri-gamboni";
    repo = "matrimail";
    tag = "v${finalAttrs.version}";
    hash = "sha256-hWwGGPHmVQ0OWhCtc5bN0vlIbsee8D6hr/utVmma80k=";
  };

  vendorHash = "sha256-bnJjYRfUdUiI6op2DONGM2HzCsQVU+V/6+RV1FiPLTE=";

  # sqlite is cgo.
  env.CGO_ENABLED = "1";

  buildInputs = [ olm ];

  subPackages = [ "cmd/matrimail" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Tag=v${finalAttrs.version}"
  ];

  meta = {
    description = "Matrix-email bridge over IMAP IDLE and SMTP submission";
    homepage = "https://github.com/moiri-gamboni/matrimail";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "matrimail";
  };
})
