# keebmouse: self-made keyboard-driven pointer (Hyper+Shift+G toggles the mode).
#
# The source repo is private, so this fetches the same signed release artifact the cask used
# rather than building from source. That distinction is the whole reason this can be a nix
# package at all: what breaks TCC is an ad-hoc signature whose cdhash changes on every rebuild,
# not nix itself. Here the bundle keeps its Developer ID signature (Yuki Kawashima, S3H296G6Q5)
# untouched, and nix-darwin copies it to a stable /Applications/Nix Apps/keebmouse.app, so
# Accessibility survives version bumps. It has to be re-granted once, for the move off
# /Applications.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "keebmouse";
  version = "0.1.1";

  src = fetchurl {
    url = "https://github.com/gapul/homebrew-tap/releases/download/v${finalAttrs.version}/keebmouse-${finalAttrs.version}-macos-arm64.zip";
    hash = "sha256-b+GRRtWO5i/oOIVIzqYDue1oYgjsXSo5mROTl2+HTOM=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";

  # Patching anything inside the bundle would invalidate the signature, which is the one thing
  # this package exists to preserve.
  dontPatchShebangs = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    # The release zip carries AppleDouble sidecars (._Info.plist, ._MacOS, …). macOS' own
    # unarchiver folds them back into extended attributes, but unzip writes them out as real
    # files, and a file the signature never sealed is exactly what breaks the seal:
    # `codesign -v` reports "a sealed resource is missing or invalid" and lists them as
    # "file added". They only carry xattrs, so dropping them restores a valid signature —
    # verified against a plain `unzip` of the same artifact, which fails the same way.
    find . -name '._*' -delete
    find . -name '.DS_Store' -delete
    mkdir -p $out/Applications
    cp -R keebmouse.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "Keyboard-driven pointer for macOS (self-made)";
    homepage = "https://github.com/gapul/keebmouse";
    platforms = [ "aarch64-darwin" ];
    mainProgram = "keebmouse";
  };
})
