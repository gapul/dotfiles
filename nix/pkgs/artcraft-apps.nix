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
    version = "0.16.0";
    hash = "sha256-SJ4Ap/0Z9+kko6Bewzx7BX6kdmEptO7xMs6C/0LBBhk=";
    linuxHash = "sha256-fBfzYz6/favydiji0mN9kYx8KlsWO4uQNHp4rN32Ngg=";
  }
  {
    name = "VectorCraft";
    version = "0.17.0";
    hash = "sha256-C9P16kcpPNalUAFGMIm+o8bZjlumV/oAZ5nCvoeHUFo=";
    linuxHash = "sha256-ZsKJ0L01S3HkzXhxk+oEgeOhzSOfKhgGgRDqNoUvwCY=";
  }
  {
    name = "FilmCraft";
    version = "0.13.0";
    hash = "sha256-ExPv3jIMJTYcG9AVxH0YzErUDJIV4eq/Ko7F22pzlu0=";
    linuxHash = "sha256-QOnWhfs+0bCiHJwCIR8ahJngmkfFUSRM5+6A8lhNOps=";
  }
  {
    name = "LightCraft";
    version = "0.14.0";
    hash = "sha256-zehZHak/e1qnrQkTfMk8Hr87R0j+ieR3uwNiY9fJPnU=";
    linuxHash = "sha256-uCM7k3PW6ZsRgMHDn9yxPUnEQfgAkncIMfqxlcTE/aI=";
  }
  {
    name = "PdfCraft";
    version = "0.14.0";
    hash = "sha256-8L3eo/DXEUcNlfcUsjzM5hw4srvMqCHTl86NuwVkz3Q=";
    linuxHash = "sha256-qT9RHof2MDbKX1MAsaehijzSKFIF3qsVOUyqbug8bx8=";
  }
  {
    name = "EffectCraft";
    version = "0.17.0";
    hash = "sha256-JBri5yzvx65w9YMBeo5rd2NwKiRoPb1khJ5WhpP5S60=";
    linuxHash = "sha256-zXrODXRzS3noUfGFN8FLKVO3/rXaJA9QBeaAVHahUpI=";
  }
  {
    name = "DesignCraft";
    version = "0.13.0";
    hash = "sha256-FNAguQ35F43ikNYk4BK9zrNTsVlf9beZHUiWuPQuoDs=";
    linuxHash = "sha256-UxTUa8Ugz1SDWi0SkzUb4f7RFiKOBVOTAZcp8E4PmcI=";
  }
  {
    name = "WordCraft";
    version = "0.11.0";
    hash = "sha256-DiAwsnFXpCvhUaKLrgOhFYnAhATRZtVdbQvd7WWw0is=";
    linuxHash = "sha256-A0wke/basXKi7fsHZ96QZRJbhXgmxpFffvObn0OVHVo=";
  }
  {
    name = "GridCraft";
    version = "0.12.1";
    hash = "sha256-7iNPUeLnR9zyeP3phMhiGP3+L/cYjAG2mTlPyu9AM74=";
    linuxHash = "sha256-HBdQ3W0mN2z4yK8itG3A7T2NXLsRXlVfD8fQz3qa6po=";
  }
  {
    name = "DeckCraft";
    version = "0.11.1";
    hash = "sha256-wLTonABLMRh4Mq/OMS8nnxX1rbfbYYCNt0YI2CJybx0=";
    linuxHash = "sha256-e/V6EKT892c+y2abZODlRUdXgO8+Tua/YDrrAPVE5pw=";
  }
  {
    name = "SoundCraft";
    version = "0.13.1";
    hash = "sha256-XNTEWGL9yd3IwqZOVl0KF+cPL00jruV0Z6SBImgUP0s=";
    linuxHash = "sha256-Ce5siEWTT+70u/TFwOLw/8o/yREm/XpqQGGx+DkHRW0=";
  }
  {
    name = "CADCraft";
    version = "0.13.0";
    hash = "sha256-U58nwfov55/i8cVi/p6wexeQ/9LNe/HkOOnHGTg66yk=";
    linuxHash = "sha256-04dVvrYYiXVr69k430kebuDeeMLzX9NRBaR5kJ/RypI=";
  }
]
