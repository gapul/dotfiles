# ArtCraft (github.com/storytold/artcraft): the studio's own AI-assisted crafting
# engine for artists and filmmakers, on a release line separate from the Craft apps
# in pkgs/artcraft-apps.nix. macOS universal dmg only (no Linux build).
#
# 7zz writes extended attributes out as `name:com.apple.*` sidecar files, which
# would break the code seal; they are deleted so the bundle stays "Notarized
# Developer ID" (Learning Machines LLC, DJ6XS33FX8).
{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "artcraft";
  version = "0.41.0";

  src = fetchurl {
    url = "https://github.com/storytold/artcraft/releases/download/artcraft-v${finalAttrs.version}/ArtCraft_${finalAttrs.version}_universal.dmg";
    hash = "sha256-PPHfLlY0XmA8XQGA5bVj3V7KJdnjw5WdlVQBL1EJFsE=";
  };

  nativeBuildInputs = [ _7zz ];

  unpackPhase = ''
    runHook preUnpack
    7zz x -snld $src
    find . -name '*:com.apple.*' -delete
    runHook postUnpack
  '';

  sourceRoot = ".";

  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R "$(find . -maxdepth 2 -name ArtCraft.app -print -quit)" $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "ArtCraft, an AI-assisted crafting engine for artists and filmmakers";
    homepage = "https://github.com/storytold/artcraft";
    platforms = lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
