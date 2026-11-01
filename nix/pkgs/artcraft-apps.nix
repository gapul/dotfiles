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
    version = "0.19.0";
    hash = "sha256-QCS1MfFMyWw9PjPcxeEsS1EU0hmgEyPQFz/VNEWf02g=";
    linuxHash = "sha256-EjOFsXMKzhjxK8D0lGBuakzT9KuJH5MDbNTnG4rqcPc=";
  }
  {
    name = "VectorCraft";
    version = "0.20.0";
    hash = "sha256-kGH/OR3w1+SoQ/n7psLT/zos8RjT9M23LyQNvb7Dixg=";
    linuxHash = "sha256-042D2eWf3PehAEFOIrMJQJT+T+LdQ6EF8EKXgBJhDoY=";
  }
  {
    name = "FilmCraft";
    version = "0.16.0";
    hash = "sha256-LXqi+96CZudVtOJXNWZzi8/7pcAdfXYARZcfF9hLX/w=";
    linuxHash = "sha256-WIOQ7uXX4WNPBXlMT4d93ylJTZz3RAURHWfBbL4hWuk=";
  }
  {
    name = "LightCraft";
    version = "0.17.0";
    hash = "sha256-ZWpNvjTtq+R49rocg49xjqZ+XKfGHBWRx74I3DYhoUs=";
    linuxHash = "sha256-0Yf1oVktSGYiDE0SfW5aPaT/p8lmzIffj0nnNcB88sE=";
  }
  {
    name = "PdfCraft";
    version = "0.17.0";
    hash = "sha256-kK7ChZAk8n4Qlez4uyUKm8AlH5ALoKtc0ZTRBVfIpxI=";
    linuxHash = "sha256-+YFKegr3e5Ba26HDB5yu3uU3WGeXBDz1r5UDkU9qvsU=";
  }
  {
    name = "EffectCraft";
    version = "0.20.0";
    hash = "sha256-1gOoA+PtwKi0QMX7zSyvm3dfhTBRAAkNOtLkwEqYusE=";
    linuxHash = "sha256-JXMQCgos4HppJXvaf6an1SUtO00y3+86H20slby42iM=";
  }
  {
    name = "DesignCraft";
    version = "0.16.0";
    hash = "sha256-7m29SZH2Nl4kLJ7aTVo4hTZwLH2Q6o4EaHp3yh0edCs=";
    linuxHash = "sha256-pIb8Q83I8kXtr3N8uxyaMoYO4YqNyhuv4IERAU4vFXY=";
  }
  {
    name = "WordCraft";
    version = "0.14.0";
    hash = "sha256-LEAmsX0CdRGgOvxKx3TGQsK2J2tv8n5wjGX98olJUKw=";
    linuxHash = "sha256-MBDaPTUtlSVuyaF6A5ZigKHUG6CdDr5WmvIwkti2SYc=";
  }
  {
    name = "GridCraft";
    version = "0.15.0";
    hash = "sha256-MvxIvRfef4q6lYT1y/1JBZgVZFMYsWnVp/VfUaVD/iU=";
    linuxHash = "sha256-aBD4znOUtafN+vOYOCV7Y4Tc65+DJQJNR124le5Z2qo=";
  }
  {
    name = "DeckCraft";
    version = "0.14.1";
    hash = "sha256-N3pi+iOYnG3MxOJp4uFHOlNLWz/pa6xi8K2WKnYiV5Q=";
    linuxHash = "sha256-6Gx/oOy1XxpVPuQluT3P3IBrezeY8nK0Hx0f90rFwSo=";
  }
  {
    name = "SoundCraft";
    version = "0.16.0";
    hash = "sha256-54psPa9proPEdl7k8XWZOvgUc5n0Yp2d+cJdr+lsMCk=";
    linuxHash = "sha256-Jcawy4kkGY8i46bydx19zJ4EGjJEpL5EXL3p0A59wZ4=";
  }
  {
    name = "CADCraft";
    version = "0.16.0";
    hash = "sha256-y3+HFzHklc7+wAOkElUMEu9noVEPYeRfff+n7f6AW74=";
    linuxHash = "sha256-FJggs9Dh5ymiJW40RSO5gFhx057jnJ4IX1B3B/c8y9Q=";
  }
]
