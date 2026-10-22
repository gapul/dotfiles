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
    version = "0.12.0";
    hash = "sha256-W0OWlGA/Ecz5OUbvR0CRr63J+xiQrYAicj0WDU/MwI0=";
    linuxHash = "sha256-+yuDAjDjICoe4Y7CDj9tJQ0naxZdeIEeg+tqdXJfnOI=";
  }
  {
    name = "VectorCraft";
    version = "0.14.0";
    hash = "sha256-KWMMnE28W+NRs3jwd1/u1henzFmbk4WcuY4/fTebzXs=";
    linuxHash = "sha256-WzSgXxI8pMxhHozmmoMQba7Y6iiLr2Phq7maQss7SG0=";
  }
  {
    name = "FilmCraft";
    version = "0.10.0";
    hash = "sha256-baLg6FS85D8IFyR8xbuuqPCaPcwSvEobP4DbokUeJwI=";
    linuxHash = "sha256-ldehr8ueICHTNxoBFwCvbOL/4a8OHP6ZxvuYs6oyD4A=";
  }
  {
    name = "LightCraft";
    version = "0.11.0";
    hash = "sha256-CaDdWp1C5rYHrFd4nWobnPj1jZpnC7Zx35ungJ9k5wg=";
    linuxHash = "sha256-otG+HFKruB9aBzZiSiDOkocYPgsJVQBYKfSp3aQUlro=";
  }
  {
    name = "PdfCraft";
    version = "0.11.0";
    hash = "sha256-h3TfMqTdw1YCmxM9fYYO1HI8louLAY4gYrOdoPsF51I=";
    linuxHash = "sha256-Da1dSyH8j9EZLouFTTjcwlf65mga4X8Q8bP0HoRIj08=";
  }
  {
    name = "EffectCraft";
    version = "0.14.0";
    hash = "sha256-W7CEGmXnY8TNJ9wLzDiilSPrLx1R6GdNRIRnAKf392U=";
    linuxHash = "sha256-f0ZOTO3NpBj4uEBjxbOnm99ZqKbApOIpv3qq8FKl2ac=";
  }
  {
    name = "DesignCraft";
    version = "0.11.0";
    hash = "sha256-mLOjfJi+UCSIZV2OOC2tHqPPgc3z944eaabRc5RXrjY=";
    linuxHash = "sha256-Egdvic5EWvXPlsAEhwGn1INz3MvVJN4Z/iMIYBtVTVg=";
  }
  {
    name = "WordCraft";
    version = "0.9.0";
    hash = "sha256-UA6Q1ybusqpFr3uwFcLRMhclFoU/lnS83scyr28Lwbg=";
    linuxHash = "sha256-j1B4AulxsWr6G23FZTF+swiF/7Kuwul206HdqkfFKdQ=";
  }
  {
    name = "GridCraft";
    version = "0.10.0";
    hash = "sha256-T/mRJVV4SOOZdokSLnqC+MEQ0J/WYVByw6JjQbcFiM8=";
    linuxHash = "sha256-t4ooYFzTRZT8Nd/BrTapJAVFcaE4JiX7dQb9cM37kZc=";
  }
  {
    name = "DeckCraft";
    version = "0.9.0";
    hash = "sha256-FZV+1JmBhEKpieyIedcBVCZsfIVJYXH6FQ5F6ixCSvk=";
    linuxHash = "sha256-UxtMjNQ0ynZ+8h2g1E4JlmSvXV2WiwOLyPkncX+PqPE=";
  }
  {
    name = "SoundCraft";
    version = "0.12.1";
    hash = "sha256-lvK89Hqykf27ljNE2/K3XnTznL2il6CmZY27FHV7ctk=";
    linuxHash = "sha256-sKVr1rXSfeaxLjVFgMNivm9ZEl6lj1cwRMhPan2od4A=";
  }
  {
    name = "CADCraft";
    version = "0.10.0";
    hash = "sha256-ZBexDDF0GOULT1v3yQ63BmrKGOKdMnY7x7OlzOW+w5Q=";
    linuxHash = "sha256-K/E6vkZFZVyXHUUjBMBvmAgYSazoajKJ/Jkb7FU5LRg=";
  }
]
