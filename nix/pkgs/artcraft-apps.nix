# ArtCraft's crafting apps (getartcraft.com/apps): open-source, pure-Rust
# clean-room takes on the Adobe suite - PhotoCraft (Photoshop), VectorCraft
# (Illustrator), FilmCraft (Premiere), LightCraft (Lightroom), PdfCraft
# (Acrobat), EffectCraft (After Effects), DesignCraft (InDesign) - plus the
# later ones outside Adobe: WordCraft (Word), GridCraft (Excel), DeckCraft
# (PowerPoint), SoundCraft (Pro Tools) and CADCraft (AutoCAD).
#
# Not in nixpkgs and no casks, so the official builds are repackaged: the universal
# dmg on darwin, the x86_64 tarball on Linux (nixos-laptop).
# All seven share one release layout under github.com/storytold, so one list.
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
    version = "0.6.0";
    hash = "sha256-rtrDEcenbbMoVFHgNgqw2m574j5d7TjIrFhA1oytdNs=";
    linuxHash = "sha256-tl/XAbY2DTugsFkAR0v5LZkmx2gC/vp76ZZpD8vDlsY=";
  }
  {
    name = "VectorCraft";
    version = "0.8.0";
    hash = "sha256-+ujZAjCVNoc7mqPGUhso2McCbP6TpRWtpO5eVIu5GXw=";
    linuxHash = "sha256-SLjmcaQV9d3pEqBJ+CzaBbZvfm/XmoG0WIFv+Rhogs8=";
  }
  {
    name = "FilmCraft";
    version = "0.5.0";
    hash = "sha256-LPWq5o3uoDfiQYWo0pp4lgGD/xXENsATGwR2IY1zPPI=";
    linuxHash = "sha256-viGD+YWcATy/Lo3ClSRTJQOj63XiFWr2F71N9/+tQN0=";
  }
  {
    name = "LightCraft";
    version = "0.5.0";
    hash = "sha256-vSMwHVHJdWyXAVYSS8xHVxtTD79183IIZj7nXG6sBJ4=";
    linuxHash = "sha256-FkFwuzdFuUz/weBdWbIHeOtRaYVYIk+Ebp4fVCTaMmU=";
  }
  {
    name = "PdfCraft";
    version = "0.5.0";
    hash = "sha256-Nr/U+x1v0iMh+SJj28l7Qcwma1J196rGMGRGS2vpgs0=";
    linuxHash = "sha256-ILNbP9CZwO8Cpye/m6267rZjnFZ0K00ERMwpdNv/X98=";
  }
  {
    name = "EffectCraft";
    version = "0.7.0";
    hash = "sha256-05T9DAQ3Kq2J+5mhYL8u7s9+YDWya/LaIJzXgZsby10=";
    linuxHash = "sha256-/+x316LjSdn7AMjruQKvwsuO9UyKLVjdQEurFfW4Q4c=";
  }
  {
    name = "DesignCraft";
    version = "0.5.0";
    hash = "sha256-ivZyAcjSxUk8dqrwNX4WvOO8KqBFTWRDnyn8SppVpyU=";
    linuxHash = "sha256-wknntpTALL+t2HgfbqP1KSbLYj1uWSTYl07WYBnsBWI=";
  }
  {
    name = "WordCraft";
    version = "0.4.0";
    hash = "sha256-kNMLI7fx84c/EI22EhjVFNjKVGXvftO6pTmo7STphlU=";
    linuxHash = "sha256-hA+YXJj/rrFSqGQhOZ5RuQXWz4vLCALs0mgtfXcjGiY=";
  }
  {
    name = "GridCraft";
    version = "0.4.0";
    hash = "sha256-TLddio6a2H11doFR2J6zolLjUn2whT6UcElctCQBmns=";
    linuxHash = "sha256-0k855lr/r1sY6/KkI+8S8FQxttI2qLE0V+e/WOMoMJw=";
  }
  {
    name = "DeckCraft";
    version = "0.4.0";
    hash = "sha256-1BFpxsHQ01Ip/mato4Vs1mm4kXyCw1cSNr37nLJMf5A=";
    linuxHash = "sha256-1gdw8NbaiH/tXHaYP0kABG2H3X+9aWVKMiBJF4lLIs4=";
  }
  {
    name = "SoundCraft";
    version = "0.4.0";
    hash = "sha256-M5dZfRVshQTxBNkE7oI2vIpJJiNIAKA0RJsIJtF7gFE=";
    linuxHash = "sha256-Ad51aYJtOQ8+QwCdI3IY30iLKOyjqEV94YLjNBIFLnc=";
  }
  {
    name = "CADCraft";
    version = "0.4.0";
    hash = "sha256-8ifNBfBWRVZUzgio6mRvYWbrYQugM+djWgY40q0vpAI=";
    linuxHash = "sha256-3lteYfsVfxrlSuCjk7V+hs0cNU/qiwhSkokPqiEM93g=";
  }
]
