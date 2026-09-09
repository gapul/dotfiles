# Bitwarden Agent Access CLI: hands an agent one credential at a time, with the human approving
# each request, instead of unlocking the whole vault for it.
#
# Why this rather than a hand-rolled broker: the shape we wanted (agent asks for a domain, a
# prompt appears here, only the approved item travels back) is exactly what Bitwarden published
# as an open protocol in March 2026, Apache-2.0, over a Noise tunnel. Writing our own would have
# been the same design with none of the review.
#
# The part that makes it usable from an agent is `aac run`: it fetches the credential and execs a
# command with it injected as environment variables, so the secret lands in the child process and
# never in the agent's transcript. `aac connect` prints the credential instead — do not call that
# one from a tool the agent can read.
#
#   aac listen                              # this side: paired with `bw`, shows the approval prompt
#   aac run --domain example.com -- cmd     # agent side: credential arrives as env vars
#
# Traffic is relayed through `wss://ap.lesspassword.dev` unless --proxy-url says otherwise. The
# tunnel is end-to-end encrypted so the relay sees ciphertext, but both ends of ours live on this
# same machine, so there is a self-hosted relay in the repo (crates/ap-relay) worth pointing at
# instead. Not packaged yet: the release tarball ships only `aac`, so the relay means building the
# Rust workspace, and cargo's crates.io fetches are unreliable from this machine.
#
# Upstream calls the SDK early alpha. Taken anyway: the alternative is not something safer, it is
# either typing passwords by hand or maintaining our own broker, and this is better than both.
#
# A single binary in a tarball, so this is a fetch and an install, not a build.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "aac";
  version = "0.11.0";

  src = fetchurl {
    url = "https://github.com/bitwarden/agent-access/releases/download/v${finalAttrs.version}/aac-macos-aarch64.tar.gz";
    hash = "sha256-XSCSPku5ZJ713yeY2aoOlbShhAzmY9MJFTQXehGCMcE=";
  };

  sourceRoot = ".";
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 aac $out/bin/aac
    runHook postInstall
  '';

  meta = {
    description = "Bitwarden Agent Access CLI: per-request, human-approved credentials for agents";
    homepage = "https://github.com/bitwarden/agent-access";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "aac";
  };
})
