# ArtCraft's crafting apps (getartcraft.com/apps): open-source, pure-Rust
# clean-room takes on the Adobe suite - PhotoCraft (Photoshop), VectorCraft
# (Illustrator), FilmCraft (Premiere), LightCraft (Lightroom), PrintCraft
# (Acrobat), EffectCraft (After Effects), DesignCraft (InDesign).
#
# Not in nixpkgs and no casks, so each official universal dmg is repackaged.
# All seven share one release layout under github.com/storytold, so one list.
# Upstream is early alpha and releases near-daily; bump version + hash here.
#
# The dmgs are HFS+ and hdiutil cannot attach inside the build sandbox, so 7zz
# reads them. 7zz writes extended attributes out as `name:com.apple.*` sidecar
# files, which would break the code seal; they are deleted so the bundles stay
# "Notarized Developer ID" (Storytold, DJ6XS33FX8).
{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:
let
  mkCraft =
    {
      name,
      version,
      hash,
    }:
    let
      pname = lib.toLower name;
    in
    stdenvNoCC.mkDerivation {
      inherit pname version;

      src = fetchurl {
        url = "https://github.com/storytold/${pname}/releases/download/v${version}/${pname}-${version}-macos-universal.dmg";
        inherit hash;
      };

      nativeBuildInputs = [ _7zz ];

      unpackPhase = ''
        runHook preUnpack
        7zz x -snld $src
        find . -name '*:com.apple.*' -delete
        runHook postUnpack
      '';

      sourceRoot = "${name} ${version}";

      dontFixup = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/Applications
        cp -R ${name}.app $out/Applications/
        runHook postInstall
      '';

      meta = {
        description = "${name}, an open-source pure-Rust creative app from ArtCraft";
        homepage = "https://github.com/storytold/${pname}";
        platforms = lib.platforms.darwin;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    };
in
map mkCraft [
  {
    name = "PhotoCraft";
    version = "0.2.0";
    hash = "sha256-1hKGg/gWyeySTODQetIsPthZmTDSzFSF/8Z9MCnTlRw=";
  }
  {
    name = "VectorCraft";
    version = "0.3.0";
    hash = "sha256-LKQfAKzeb7k4BHFD0OInwXH1mv7iTqHwwmzr3gt1PZc=";
  }
  {
    name = "FilmCraft";
    version = "0.2.0";
    hash = "sha256-Fw5YhzU6qdgRnhlUP6fs/b/3x6ERODUvlnMdbTVLeFA=";
  }
  {
    name = "LightCraft";
    version = "0.2.0";
    hash = "sha256-8acRVOMdA8pLtw2Tr9PiozVUyWQOXv+BMkbri57O1nc=";
  }
  {
    name = "PrintCraft";
    version = "0.2.0";
    hash = "sha256-I+B+elhB6uJU3aNXIDN0E899STXYK15i2mVFntXfRZU=";
  }
  {
    name = "EffectCraft";
    version = "0.3.0";
    hash = "sha256-rkjJPBLRtyros5VI40FC38PvScRhVr/pscWIByBYY/A=";
  }
  {
    name = "DesignCraft";
    version = "0.2.0";
    hash = "sha256-gp2uT+p4QNVNn/kVug+m5ZxmY6jsQU7l49ZgF10rRlg=";
  }
]
