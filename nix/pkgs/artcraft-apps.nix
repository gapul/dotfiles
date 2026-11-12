# ArtCraft's crafting apps (getartcraft.com/apps): open-source, pure-Rust
# clean-room takes on the Adobe suite - PhotoCraft (Photoshop), VectorCraft
# (Illustrator), FilmCraft (Premiere), LightCraft (Lightroom), PdfCraft
# (Acrobat), EffectCraft (After Effects), DesignCraft (InDesign) - plus the
# later ones outside Adobe: WordCraft (Word), GridCraft (Excel), DeckCraft
# (PowerPoint), SoundCraft (Pro Tools) and CADCraft (AutoCAD).
#
# Not in nixpkgs and no casks, so the official builds are repackaged: the universal
# dmg on darwin, the x86_64 tarball on Linux (nixos-laptop).
# All twelve share one release layout under github.com/storytold, so one list.
# Upstream is early alpha and releases near-daily; bump version + hash here.
#
# The dmgs are HFS+ and hdiutil cannot attach inside the build sandbox, so 7zz
# reads them. 7zz writes extended attributes out as `name:com.apple.*` sidecar
# files, which would break the code seal; they are deleted so the bundles stay
# "Notarized Developer ID" (Storytold, DJ6XS33FX8).
{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  _7zz,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  dbus,
  libGL,
  libxkbcommon,
  vulkan-loader,
  wayland,
  libx11,
  libxcursor,
  libxi,
  libxcb,
}:
let
  mkCraftDarwin =
    {
      name,
      version,
      hash,
      ...
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

  # The Linux builds link only libc, libgcc and (FilmCraft/EffectCraft) ALSA; the
  # window, GPU and portal libraries are dlopen()ed at runtime (winit, wgpu, zbus),
  # which autoPatchelf cannot see, so they go on LD_LIBRARY_PATH instead.
  runtimeLibs = [
    vulkan-loader
    libGL
    wayland
    libxkbcommon
    libx11
    libxcursor
    libxi
    libxcb
    dbus
  ];

  mkCraftLinux =
    {
      name,
      version,
      linuxHash,
      ...
    }:
    let
      pname = lib.toLower name;
    in
    stdenv.mkDerivation {
      inherit pname version;

      src = fetchurl {
        url = "https://github.com/storytold/${pname}/releases/download/v${version}/${pname}-${version}-linux-x86_64.tar.gz";
        hash = linuxHash;
      };

      nativeBuildInputs = [
        autoPatchelfHook
        makeWrapper
      ];
      buildInputs = [
        stdenv.cc.cc.lib
        alsa-lib
      ];

      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -R bin share $out/
        for b in $out/bin/*; do
          wrapProgram "$b" --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
        done
        runHook postInstall
      '';

      meta = {
        description = "${name}, an open-source pure-Rust creative app from ArtCraft";
        homepage = "https://github.com/storytold/${pname}";
        platforms = [ "x86_64-linux" ];
        mainProgram = pname;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    };

  mkCraft = if stdenvNoCC.hostPlatform.isDarwin then mkCraftDarwin else mkCraftLinux;
in
map mkCraft [
  {
    name = "PhotoCraft";
    version = "0.23.0";
    hash = "sha256-jKdh8+mvTZMsxu/dbsv6IhKBU7owzOlVVHymJW5hUW0=";
    linuxHash = "sha256-mFjuI0hU98OQ8+q0c0rqUxAMyRLCyNzqoClCe3XdIvg=";
  }
  {
    name = "VectorCraft";
    version = "0.24.0";
    hash = "sha256-8aBHEnN0La0NTTeTS1pgzXWuFj2OXhuM83OaRxl7rxI=";
    linuxHash = "sha256-nGFxygB6b4NcNotZL+nukMmF1lBX7cnc0rxMTvxQrSs=";
  }
  {
    name = "FilmCraft";
    version = "0.20.1";
    hash = "sha256-VyLw8hypZYPuJ9/Yi64j4KSmq4eGKmwACCyIxcdZ514=";
    linuxHash = "sha256-Pk/qPLjUc+aPGJoKh5K6RhYPq1B62rOriSAHP9QfJPo=";
  }
  {
    name = "LightCraft";
    version = "0.21.0";
    hash = "sha256-3TzVtU3w19ekV+APP61+VQgT1N+KjNqhpr3PcCH7Kz0=";
    linuxHash = "sha256-fn2lU96hACaKBY8TXHxK0fT7drTYJC4U9w8W7YkllYA=";
  }
  {
    name = "PdfCraft";
    version = "0.21.0";
    hash = "sha256-wYwT6k7a79vzzyMfhRIxqK5RzxUHdy7aaTtZF0y6pq8=";
    linuxHash = "sha256-eajHbiOtbmcd47hWpHaTavwAD4qn/v/xkNQ95i+jW6E=";
  }
  {
    name = "EffectCraft";
    version = "0.24.1";
    hash = "sha256-ItARHR2qpxQu5iZqK4F00vTTdcTBLg38QKBNs9+zWFE=";
    linuxHash = "sha256-XOA5NpAUQif6kYboIwitY4pu9tn5dsmW5tA7W1G2Wns=";
  }
  {
    name = "DesignCraft";
    version = "0.20.1";
    hash = "sha256-9Fsr9VQ8HYw30JqXHplCDW7z2XtuvjPjGzbSo8OesMI=";
    linuxHash = "sha256-6RYw1M31eMyx4vOfiOJOhSDxSC1RrkcUZX7kceIjf0Q=";
  }
  {
    name = "WordCraft";
    version = "0.18.1";
    hash = "sha256-ifbgqRD4rVqBXYAkx5Mk0gW1b80uBd7tAQ6QFvWBPew=";
    linuxHash = "sha256-MSoFfUbdgFl8EtzP0Ql84l7epAuqrrULy28BrBrrrbU=";
  }
  {
    name = "GridCraft";
    version = "0.19.1";
    hash = "sha256-1QFl54uONau+aKp8bzbCkAI97GUNiqeXrCNHqTD2wZc=";
    linuxHash = "sha256-jZe7otW7AP1p7VUGSFLB/ZFN5A1ezVXKAcjfgbgolG0=";
  }
  {
    name = "DeckCraft";
    version = "0.18.1";
    hash = "sha256-MyHRH2NTs/+d4yjyFAfXUn8fkCnIPatOOrc09RbToFU=";
    linuxHash = "sha256-W659VWZjhiRBHvlo8lMqszWNwoCIQURYPkl8VjHbiiY=";
  }
  {
    name = "SoundCraft";
    version = "0.20.1";
    hash = "sha256-6x3TktfDhntWmqngjAFkJwloAAFv8z+PTgGS5D2ebAs=";
    linuxHash = "sha256-yu/PhcTxE4cX1ZLTHOW+B/L8phbsNtY/rGdgze++KKk=";
  }
  {
    name = "CADCraft";
    version = "0.20.1";
    hash = "sha256-ye8c8CI05qXoVCh6ZP4xStbVMieRXDxmZPpBYeKh/nA=";
    linuxHash = "sha256-V7bxtBtPPFQqgvEDIC7Rp3lEDl/40lwI72ar2hqMsbk=";
  }
]
