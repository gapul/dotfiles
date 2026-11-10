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
    version = "0.22.0";
    hash = "sha256-AnWW3LE9sMDXSTFcBSSTv1h4hunQga+lfLxldaTN5uk=";
    linuxHash = "sha256-7t6vpGdd+9HyNR5r+kuC9URTaU6zbaG71cqLv19U8gI=";
  }
  {
    name = "VectorCraft";
    version = "0.23.0";
    hash = "sha256-i+48VClIfnCPlUacZWj3UMcA+XuGSDpvbL/Qdpslvhs=";
    linuxHash = "sha256-B8JKYJT7RXxmW5WEjVW/vQVGA1S8DqybTsn5RnqLHjE=";
  }
  {
    name = "FilmCraft";
    version = "0.19.0";
    hash = "sha256-MaM+5Gs5rZr4wQZ0x1ZRTHHTE7seaLVDXJ7NcbRr7FQ=";
    linuxHash = "sha256-dhSTQ8GXALpqyQX96KAZ4JF9BlB/QmpZODltl6HKISQ=";
  }
  {
    name = "LightCraft";
    version = "0.20.0";
    hash = "sha256-3bNMjIe7Ba0sKVBS4wJjY2hteZWwi8/lDmzZimtnppc=";
    linuxHash = "sha256-jLXu2CWy3Z4PpCaAEp0+WqcY8HGW1nzF0FdB8OapzCU=";
  }
  {
    name = "PdfCraft";
    version = "0.20.0";
    hash = "sha256-9EvqFGb8tpAu/7rX6CT+WacAd8c+vZd+FOFmWFxEfOY=";
    linuxHash = "sha256-Gg8px6auBJFhJiMdhDsuqDaiG42wny70FpUQFaQ36Lw=";
  }
  {
    name = "EffectCraft";
    version = "0.23.1";
    hash = "sha256-EHA64LiyeSQeeoe2m/pa4CE8whpnoE6peOhDCfbo4vg=";
    linuxHash = "sha256-ozDRQG/ecdB6xVrTf+gfXeN+x+p8p8O5+gKqzQRQLbE=";
  }
  {
    name = "DesignCraft";
    version = "0.19.0";
    hash = "sha256-OfKkX4JUFsRqAyjNJgA6hrjwlj/so2xEa/sg4LgZC3g=";
    linuxHash = "sha256-UFVTH+n2Dk2mETdw/s8n37A5hPgx+k7XBzC+FWoxaGY=";
  }
  {
    name = "WordCraft";
    version = "0.17.0";
    hash = "sha256-vl2JojkFw6kd9NWPAPgnrAaqjFDL60Hm59n337hkpYo=";
    linuxHash = "sha256-nHRMDDGjziXfgmgPx15kXWgoRvrMvhA/T5GnWLGfNoc=";
  }
  {
    name = "GridCraft";
    version = "0.18.0";
    hash = "sha256-NdlrpvqLv5CWL7zpdrkgaIfWepOCfha79Dj4qRUUDdM=";
    linuxHash = "sha256-aSBf1y5I6D52PFPI9so+3AHTi6i6DRbisYSpyFikzV8=";
  }
  {
    name = "DeckCraft";
    version = "0.17.0";
    hash = "sha256-32GlQpfwIiST1dk2w9W+Bfk4ALXw2NES2AXFQuNbiEg=";
    linuxHash = "sha256-phoFCVpSqAmQqomQtEcQBVPpnI+m7ch1SqUnQKGm+bA=";
  }
  {
    name = "SoundCraft";
    version = "0.19.0";
    hash = "sha256-lLZJUDtoxwsEjxLleOhZvuUcp9cY2wsC+VWgayipaW8=";
    linuxHash = "sha256-iaKb9Iwpnu5ZPXzWhLIchIPKKHq8GWZXrj+Vmh68GK0=";
  }
  {
    name = "CADCraft";
    version = "0.19.0";
    hash = "sha256-06PC3F/plFur+qQgcWYCgSw8POyLD7OrJQLvXni5YLM=";
    linuxHash = "sha256-plTfjD5EfGLEkMCoqtjEKp+vqwEMpNJbw1BO1Fs8j1E=";
  }
]
