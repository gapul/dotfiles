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
    version = "0.20.1";
    hash = "sha256-VIZVXcdJ3xZQ8yHjY1NOYDp8T4DqMcVNnohIn/dC2wM=";
    linuxHash = "sha256-OYeH1Y/kaRnpnJ9W41VFVJ7wqqsAf4aakr7/fZ/lIjQ=";
  }
  {
    name = "VectorCraft";
    version = "0.21.0";
    hash = "sha256-zudDTdUtfng9P5gQ7gCPOpO4c9paXseAGmcOqTeHx+I=";
    linuxHash = "sha256-L/0A+zSTGOfpLpevN3z/2BjxcmRRt/IYnpLyJn6zTCE=";
  }
  {
    name = "FilmCraft";
    version = "0.17.0";
    hash = "sha256-WVWPvk60SJWRwMsjLJe4i5Eg5iTeAcJtgt4QwVdvKrM=";
    linuxHash = "sha256-3z+KsjSBoo7vt8n9jTiZ+9lLsUPhlwaLRhP+BQKXv78=";
  }
  {
    name = "LightCraft";
    version = "0.18.0";
    hash = "sha256-88syaiAqLW+JvS0IzNixCOjv4QO7naiMKjjlKin5Plo=";
    linuxHash = "sha256-8tyqKH1RD5ElJz2dFgiecTlDrvAFvQPZhI2VrFXYdQ8=";
  }
  {
    name = "PdfCraft";
    version = "0.18.1";
    hash = "sha256-VfhL5WOI1p8k3yJSL21CT42OaVKdtmnOCOoZhFXgjOs=";
    linuxHash = "sha256-Qaa5+xaXDNNhDQXZhZlwAuQZv1J4+Gr2q0gHg/ib8fw=";
  }
  {
    name = "EffectCraft";
    version = "0.21.0";
    hash = "sha256-7fMR7SW3XaF5PICKNzNuAKNT5zPWV/ZO3cNfCZm2aWY=";
    linuxHash = "sha256-A/vJmKl5D6lJuQMzWXQM5mENt9GUJvDzgC9T6nDLgk0=";
  }
  {
    name = "DesignCraft";
    version = "0.17.1";
    hash = "sha256-Tl9Yz77tcOVczg7DD3gQYJL1BdIMp9xyGhyu+BlAjIY=";
    linuxHash = "sha256-o9cXIQJaGx7HLz3c70CQT22+TYJQNYbQNGXMWvH8uYY=";
  }
  {
    name = "WordCraft";
    version = "0.15.1";
    hash = "sha256-juWUNjKOJFGDhsbPFAf3xsCB/KynA85eUxCTivfasS8=";
    linuxHash = "sha256-jG/KOAnqGsgWjE19k5LK3oSlD1QBi+H4gSG6TswEpVI=";
  }
  {
    name = "GridCraft";
    version = "0.16.0";
    hash = "sha256-GkDj12z9T6lF0ed/PrpJsbcYgTPqU64I9JwpPDaWWB0=";
    linuxHash = "sha256-TFwiMYa9HpT+2f7a88v3eprJbdRaMr82RI/AIwZvE98=";
  }
  {
    name = "DeckCraft";
    version = "0.15.0";
    hash = "sha256-4+wNBjWGhCo0hlqCsXnLwwSPtO05Y/OOFRhZeil/X1c=";
    linuxHash = "sha256-TjmoBFLELsLgASJYbwiKmrJ1AySa5nz0vbE5ENSjruQ=";
  }
  {
    name = "SoundCraft";
    version = "0.17.0";
    hash = "sha256-JHRLOfcUnVcMerEKd41uoXiuYGUZLqvngr8p2daiuLw=";
    linuxHash = "sha256-MJv+y7METBbwogDWS1izQYNAifp4IR9yKvtQ6wVWbXE=";
  }
  {
    name = "CADCraft";
    version = "0.17.0";
    hash = "sha256-FWGciKG7fgFJ8D53BpHMvx9HngXdH/b3X0FtYeVbG9k=";
    linuxHash = "sha256-iZlrF2T/FWloV+CJTWC4RWkFEFGBj2SA6bf4I8dqRuQ=";
  }
]
