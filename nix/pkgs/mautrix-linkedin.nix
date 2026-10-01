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

  # Send the identity of the browser the cookies come from. Upstream hard-codes
  # Chrome 141 on Linux (pkg/linkedingo/client.go) while X-LI-Track carries the real
  # browser's details; LinkedIn reads the mismatch as a stolen session, clears li_at
  # and every voyager call 401s a few seconds after login (mautrix/linkedin#61, open).
  # On 2026-10-01 that left all 14 portals empty. The cookies are taken from the
  # terminal-browser pane on the Mac, so match that: Chromium 150 on macOS. Logging in
  # from a different browser means updating these strings to that browser's
  # navigator.userAgent / userAgentData. Drop this once #61 lands upstream.
  postPatch = ''
    substituteInPlace pkg/linkedingo/client.go \
      --replace-fail 'const ChromeVersion = "141"' 'const ChromeVersion = "150"' \
      --replace-fail 'const UserAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/" + ChromeVersion + ".0.0.0 Safari/537.36"' \
        'const UserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) terminal-browser/43.3.0 Chrome/150.0.7871.212 Electron/43.3.0 Safari/537.36"' \
      --replace-fail 'const SecCHUserAgent = `"Chromium";v="` + ChromeVersion + `", "Google Chrome";v="` + ChromeVersion + `", "Not-A.Brand";v="99"`' \
        'const SecCHUserAgent = `"Not;A=Brand";v="8", "Chromium";v="` + ChromeVersion + `"`' \
      --replace-fail 'const OSName = "Linux"' 'const OSName = "macOS"'
  '';

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
