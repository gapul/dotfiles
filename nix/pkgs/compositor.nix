# Compositor (robbietilton.com/compositor): a native, open-source Photoshop-style
# compositing editor for macOS (layers, masks, blend modes, adjustment layers).
#
# No nixpkgs package and no cask, so the official dmg is repackaged. The bundle
# carries Sparkle, but an update it installs is overwritten on the next rebuild;
# bump version + hash here instead.
#
# The app is sandboxed, so an invalid seal stops it from launching. 7zz writes
# extended attributes out as `name:com.apple.*` sidecar files inside
# Sparkle.framework, which breaks the seal; deleting them restores
# "Notarized Developer ID" (Wonder Assembly LLC, 3E4X3B9Z9T).
{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "compositor";
  version = "1.4.9";

  src = fetchurl {
    url = "https://github.com/robbietilton/Compositor/releases/download/v${finalAttrs.version}/Compositor.dmg";
    hash = "sha256-t3/R3cjrRgeFNtiXMQXy3pcFG/vZDAHJwQqXSRHoMf8=";
  };

  nativeBuildInputs = [ _7zz ];

  unpackPhase = ''
    runHook preUnpack
    7zz x -snld $src
    find . -name '*:com.apple.*' -delete
    runHook postUnpack
  '';

  sourceRoot = "Compositor";

  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R Compositor.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "Open-source Photoshop-style image compositor for macOS";
    homepage = "https://github.com/robbietilton/Compositor";
    platforms = lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
