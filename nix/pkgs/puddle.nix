# Puddle: self-built MIT fork of Plash (set any web page as the desktop wallpaper).
#
# Same shape as pkgs/keebmouse.nix: fetch the signed release artifact instead of building from
# source, so the Developer ID signature (Yuki Kawashima, S3H296G6Q5) survives. nix-darwin copies
# the bundle to a stable /Applications/Nix Apps/Puddle.app, so nothing here depends on a store
# path that moves per version.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "puddle";
  version = "2.24.0";

  src = fetchurl {
    url = "https://github.com/gapul/homebrew-puddle/releases/download/v${finalAttrs.version}/Puddle-${finalAttrs.version}.zip";
    hash = "sha256-49o9otssKquhTr61y5ORpO5nQAeCHSE0wRfUJGeHb70=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";

  dontPatchShebangs = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    # unzip writes AppleDouble sidecars (._Info.plist, ._MacOS, …) out as real files where
    # macOS' own unarchiver folds them into extended attributes. A file the signature never
    # sealed is what breaks the seal, so drop them — see pkgs/keebmouse.nix for the full note.
    find . -name '._*' -delete
    find . -name '.DS_Store' -delete
    mkdir -p $out/Applications
    cp -R Puddle.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "Set any web page as the desktop wallpaper (MIT fork of Plash)";
    homepage = "https://github.com/gapul/Puddle";
    platforms = [ "aarch64-darwin" ];
  };
})
