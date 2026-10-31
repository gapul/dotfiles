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
    version = "0.18.0";
    hash = "sha256-IDNdqr7az+2R+leed6KsGNJhpzUFd4K4dJKCeHbLD5E=";
    linuxHash = "sha256-S4rI4RRqyal+e/3vFrJn1Tlqd4Cf1OIym4Pa14CGV08=";
  }
  {
    name = "VectorCraft";
    version = "0.19.0";
    hash = "sha256-YOA/hF0wUnP4j6MYkKZ3Y4F8GykcMD7wtSkBhJAvx30=";
    linuxHash = "sha256-rlN4iPSWkZqosxk+om8F/SWEvgDv+G2AoH4mRPEGHpI=";
  }
  {
    name = "FilmCraft";
    version = "0.15.0";
    hash = "sha256-o4pAUW62DWokdBsJ8ewsdju0DgHsoa8R/W3gvFOji/Q=";
    linuxHash = "sha256-IrEGtMpilNmz6aSvQLQKZToYl0NzZIBQRqAd26pLIsE=";
  }
  {
    name = "LightCraft";
    version = "0.16.0";
    hash = "sha256-j/Ghw9GphZVcvGVx0fuojjdUuwzM6IPoMtws0+c6UXU=";
    linuxHash = "sha256-0i7fWsQBACkdjD2N3ovxyRyuIaC1bUypzAAm2zE5qSY=";
  }
  {
    name = "PdfCraft";
    version = "0.16.1";
    hash = "sha256-E1fm8c3B0Gq07MJT6cezG3HkAYl7XHgVg8yu/RlBZC8=";
    linuxHash = "sha256-uzbgcdEKFK9RISmaDu2NfF245cdYC2y+vsCFxB0b/go=";
  }
  {
    name = "EffectCraft";
    version = "0.19.0";
    hash = "sha256-K3W8pTKgb2awQVC4NYU/QQKIIddLa641fyIyU1wL5FA=";
    linuxHash = "sha256-fsk5Ha53X3zn5ykSaPexIzIowbreg87YhAMDU1yVGXA=";
  }
  {
    name = "DesignCraft";
    version = "0.15.2";
    hash = "sha256-79MKZLNr8Cz/hoeqI0VpIXvwk2GH3IFxfiLwTKXCS50=";
    linuxHash = "sha256-57eC90ZJd+/pNa1o48kIsJOfO2ZgcMiN8gRhmNxuiUQ=";
  }
  {
    name = "WordCraft";
    version = "0.13.2";
    hash = "sha256-axQrjwBUJEmjJYH4MuKTjHzXYovguWn8WC9XH33uJtA=";
    linuxHash = "sha256-bPT8wDCi1PuvM0+dbGDXPCof3uKmlRwGfl+hFf4Qc48=";
  }
  {
    name = "GridCraft";
    version = "0.14.2";
    hash = "sha256-eALyq/LEjgD9pEdaSPfPGcCZ0ABK6bEbEeKF3c8BxLQ=";
    linuxHash = "sha256-nIFTt2MK373vgCGqm5guHvGHts8nzSIzKAz68LpqGEI=";
  }
  {
    name = "DeckCraft";
    version = "0.13.1";
    hash = "sha256-nkJs6kfXj9Nx3/9Mmle/7x3f5ZLDh26G158ovKrpDMc=";
    linuxHash = "sha256-cR7AlbWQ+8uqq8jFklqDUN6pjukxq3tE1Ir2iy5h9RQ=";
  }
  {
    name = "SoundCraft";
    version = "0.15.0";
    hash = "sha256-9qZOB33erzk96S5OcQk6kfmM2KAvL0wgyzGMNsgXYYU=";
    linuxHash = "sha256-Fu8j72LsIPX8xT4Eq6r/UnCV5QX1YItHqxtyscjp7SA=";
  }
  {
    name = "CADCraft";
    version = "0.15.1";
    hash = "sha256-Q5PmSSj4p95lvoW15wmA+WvAN2NmH9DjVHEiHnMiuY4=";
    linuxHash = "sha256-0ETw+KdVxrab3GtFNh2rzDQsFOOxkZw59UBp/80cT4A=";
  }
]
