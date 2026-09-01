# keystats: self-made keystroke analytics (CGEventTap → SQLite, SwiftUI viewer).
#
# Same shape as pkgs/keebmouse.nix: the signed release artifact is fetched rather than built, so
# the Developer ID signature (Yuki Kawashima, S3H296G6Q5) is preserved and the Input Monitoring /
# Accessibility grants survive version bumps at the stable /Applications/Nix Apps path.
#
# The cask also exposed the daemon as a `keystats` binary, so keep that. What is deliberately NOT
# carried over is the cask's self-updater: it ran keystats-update daily against a writable
# /Applications copy, and with the version pinned by flake.lock that is both impossible (the
# store is read-only) and redundant. home/darwin.nix retires its agent.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "keystats";
  version = "0.10.7";

  src = fetchurl {
    url = "https://github.com/gapul/keystats/releases/download/v${finalAttrs.version}/keystats-${finalAttrs.version}-macos-arm64.zip";
    hash = "sha256-FzOCqIcPITPf+GZ1gBD3EVgAkZKFdjIu2LdJshoOOOM=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";

  dontPatchShebangs = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    # See pkgs/keebmouse.nix: unzip materialises AppleDouble sidecars that the signature never
    # sealed, and their presence alone makes `codesign -v` fail.
    find . -name '._*' -delete
    find . -name '.DS_Store' -delete
    mkdir -p $out/Applications
    # The zip nests the bundle under a versioned directory, the way the cask's
    # `app "keystats-#{version}/Keystats.app"` said it did.
    cp -R keystats-${finalAttrs.version}/Keystats.app $out/Applications/
    # A symlink rather than a copy: the daemon has to stay inside the signed bundle, or it loses
    # the identity its TCC grant is pinned to.
    mkdir -p $out/bin
    ln -s $out/Applications/Keystats.app/Contents/MacOS/keystatsd $out/bin/keystats
    runHook postInstall
  '';

  meta = {
    description = "Self-made keystroke analytics for macOS";
    homepage = "https://github.com/gapul/keystats";
    platforms = [ "aarch64-darwin" ];
    mainProgram = "keystats";
  };
})
