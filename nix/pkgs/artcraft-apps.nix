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
    version = "0.20.2";
    hash = "sha256-ifLtTUpzfsiqpXAWWBW6sKgk3z9FNJOwpQH5FReemlU=";
    linuxHash = "sha256-CeAT1o2DE+sLHNbyRhL1tf0NmT//46fBLOzf5c0TGkY=";
  }
  {
    name = "VectorCraft";
    version = "0.21.1";
    hash = "sha256-J/1NPtRy2S62gVTKdc8ly4VmgmJnFWMrKrrCVR88CL8=";
    linuxHash = "sha256-ODu6BvvefLh8fhN5N61RappYVJHFqSfYYx7lS78dTpM=";
  }
  {
    name = "FilmCraft";
    version = "0.17.1";
    hash = "sha256-ygHv70Hx5Xu1oZ1wxflOZN06NdZRUsVNEn+Kj3AaJB0=";
    linuxHash = "sha256-OXrp/s5VmzeGO0sHavRqY7bkOHw194Fwnk760U/nHr4=";
  }
  {
    name = "LightCraft";
    version = "0.18.1";
    hash = "sha256-BVNIyAmOYkTkPLwlJukVhyZ0bUZ/kZ2uM2hI23u22/k=";
    linuxHash = "sha256-B4+OT+9sqIr6JXpwIoYwsU4hOAzqWAMfu1xaGUK0BvA=";
  }
  {
    name = "PdfCraft";
    version = "0.18.2";
    hash = "sha256-edYsEfTCjVRHzuOlFjwdvwTfJAoIZAI384ULtybdKKc=";
    linuxHash = "sha256-MjutezczkgdkYeLK1dtjsi9HoDK6AFpsSjXzSD0F2uQ=";
  }
  {
    name = "EffectCraft";
    version = "0.21.1";
    hash = "sha256-rHAJf+A4ce+I6kTEKLJjmqM0ZTmwJzwRHkFsMrhOdyA=";
    linuxHash = "sha256-7DmvpR+wosC1iowRAjJeI1UBb+dUVj0kB1+imz4cUxU=";
  }
  {
    name = "DesignCraft";
    version = "0.17.2";
    hash = "sha256-Ta/RAg6FfCDTJNRiJVN9otx6b5GyAq43PuNn7IyXGVE=";
    linuxHash = "sha256-uS6QZ9sRuN4bs0gjLAlV0yRpNm+jlS1d2WwYyhgKKM4=";
  }
  {
    name = "WordCraft";
    version = "0.15.2";
    hash = "sha256-HOEg4JqoQv4kqC8PACPYUEFrwfC+9uSEjb/LadYN2t8=";
    linuxHash = "sha256-Nm5U4jW0Yxd5wMeMB3eogN5REWPekTCreM5ZWD96C5o=";
  }
  {
    name = "GridCraft";
    version = "0.16.1";
    hash = "sha256-9zXqAaif7O75TuvCU0V6+ywUY+334Kc1FlHAdaD+y4E=";
    linuxHash = "sha256-Qp4DNM3TDtdev/WUU6ZEEUw8t+M0eZGoGzIEHXX0H+Q=";
  }
  {
    name = "DeckCraft";
    version = "0.15.1";
    hash = "sha256-v+83A93+TC+1kUGdehk3SD494oBESKfyYpZfPF3NyTs=";
    linuxHash = "sha256-4tRRKdSw9dKCIyRVtzs10twWpPWHv2mh24CTmwreeM0=";
  }
  {
    name = "SoundCraft";
    version = "0.17.1";
    hash = "sha256-8Xr+NyW0CzU1ggd7ml3m0UBFL/HdXDFckzPUn4m84oc=";
    linuxHash = "sha256-56wUC7n9aa3k3QJkOvjl1MFKXILNZwsgMOUmiP67PLQ=";
  }
  {
    name = "CADCraft";
    version = "0.17.1";
    hash = "sha256-SI2XmDFBw/G/q/k0LAjB1k3dmB6MGoMWtMD8lyIcHBw=";
    linuxHash = "sha256-3aFlovLubh70nHzAJXteA4LetUHY6uAhExdogvny7AA=";
  }
]
