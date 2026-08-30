# Lightpanda: a headless browser written from scratch in Zig, for automation rather than viewing.
#
# It exists here to make the background path cheap. Measured on this machine: `lp serve` sits at
# 19MB resident, against 296MB for the Chrome that Playwright normally drives (and 302MB for
# Chrome's own `--headless=new`, which is also unusable because the Claude in Chrome extension's
# native host does not start under it). Fifteen times lighter for the jobs that only need a DOM.
#
# It speaks CDP, so it drops in wherever Chrome did: `/json/version` answers with
# Protocol-Version 1.3 and a webSocketDebuggerUrl, and playwright-mcp connects to it unchanged.
#
# What it cannot do: pages whose hydration touches APIs Lightpanda has not implemented come back
# empty rather than erroring, and it has none of the Chrome profile's cookies, so anything behind
# a login or a captcha still belongs on the real Chrome. The split is in CLAUDE.md.
#
# A single 76MB binary with no dependencies, so this is a fetch and an install, not a build.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "lightpanda";
  version = "0.3.7";

  src = fetchurl {
    url = "https://github.com/lightpanda-io/browser/releases/download/${finalAttrs.version}/lightpanda-aarch64-macos";
    hash = "sha256-rplULYGvIwhyluwDersNV6VwAlAvX/TBsLBd+khLebg=";
  };

  dontUnpack = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/lp
    runHook postInstall
  '';

  meta = {
    description = "Headless browser designed for AI and automation";
    homepage = "https://lightpanda.io/";
    license = lib.licenses.agpl3Only;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "lp";
  };
})
