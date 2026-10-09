# ArtCraft's crafting apps (getartcraft.com/apps): open-source, pure-Rust
# clean-room takes on the Adobe suite - PhotoCraft (Photoshop), VectorCraft
# (Illustrator), FilmCraft (Premiere), LightCraft (Lightroom), PdfCraft
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

      # The volume folder is "<Name> <version>" for most apps but just "<Name>" for
      # some releases, so the bundle is located rather than assumed.
      sourceRoot = ".";

      dontFixup = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/Applications
        cp -R "$(find . -maxdepth 2 -name ${name}.app -print -quit)" $out/Applications/
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
    version = "0.5.0";
    hash = "sha256-3/jIEF1ZONRvpLopVZ0+/A8eoZWlOS02z2K8FOot5ec=";
  }
  {
    name = "VectorCraft";
    version = "0.7.0";
    hash = "sha256-yZdkGfA4wOzsLaVppK/BcXwv/a9Ux6tA0msMfwZv+p4=";
  }
  {
    name = "FilmCraft";
    version = "0.4.0";
    hash = "sha256-gf7u3WKUV5/lHwes/y+LrFfCynKgtJl373a+Z8fEUjc=";
  }
  {
    name = "LightCraft";
    version = "0.4.0";
    hash = "sha256-x05FIwpUvOCb+Gzs7n4i8zdO5G+Lp3nd2j9O55ENP1w=";
  }
  {
    name = "PdfCraft";
    version = "0.4.0";
    hash = "sha256-dA2kkA6LxJVzgu8+83tUThne6UvXBPfcSaGzBuJU+hA=";
  }
  {
    name = "EffectCraft";
    version = "0.6.0";
    hash = "sha256-K46Zt/Hkl+0PcnPPIQhNI4WFAHNOn7dV6GmlsIVJdco=";
  }
  {
    name = "DesignCraft";
    version = "0.4.0";
    hash = "sha256-bEalS/C5kPz6geo4SbrVtnOlPt4GqVgMw/wc3+gtpa4=";
  }
]
