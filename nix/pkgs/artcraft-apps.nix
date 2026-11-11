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
    version = "0.20.0";
    hash = "sha256-bM6qDmpfemhIwSixO+G2abwOWmn0rrNi2XEgx8yizIg=";
    linuxHash = "sha256-NUZdcb3hifUMrK8+T9icTKY3f6+OtI6qLwZbjlRZMjY=";
  }
  {
    name = "LightCraft";
    version = "0.20.0";
    hash = "sha256-3bNMjIe7Ba0sKVBS4wJjY2hteZWwi8/lDmzZimtnppc=";
    linuxHash = "sha256-jLXu2CWy3Z4PpCaAEp0+WqcY8HGW1nzF0FdB8OapzCU=";
  }
  {
    name = "PdfCraft";
    version = "0.21.0";
    hash = "sha256-wYwT6k7a79vzzyMfhRIxqK5RzxUHdy7aaTtZF0y6pq8=";
    linuxHash = "sha256-eajHbiOtbmcd47hWpHaTavwAD4qn/v/xkNQ95i+jW6E=";
  }
  {
    name = "EffectCraft";
    version = "0.24.0";
    hash = "sha256-fkqmIrHTZ8vmNp01g5DJA+4Q7/Ee6DBk70IWQCihUi4=";
    linuxHash = "sha256-l7Ws6bjL44qF/k7dAuR+vfQnKTML0oC6IHTAiblrUCI=";
  }
  {
    name = "DesignCraft";
    version = "0.20.0";
    hash = "sha256-r69Rb9c4Eo2OVXBmSs+wLyYG/0m6AgO1nf3qvRscDUM=";
    linuxHash = "sha256-b3IQO2+iPct3vteUt6MBGJoqd6SMtjBadtvTMWmm6N4=";
  }
  {
    name = "WordCraft";
    version = "0.17.0";
    hash = "sha256-vl2JojkFw6kd9NWPAPgnrAaqjFDL60Hm59n337hkpYo=";
    linuxHash = "sha256-nHRMDDGjziXfgmgPx15kXWgoRvrMvhA/T5GnWLGfNoc=";
  }
  {
    name = "GridCraft";
    version = "0.19.0";
    hash = "sha256-riZg+7Ioy5oZo/5fcQ02uoIWFZF3sNJZ7qoIWdq+FGI=";
    linuxHash = "sha256-47HPSpJuKvp+isIukIt833uvYQO7RE+Za/oLw9iJrbY=";
  }
  {
    name = "DeckCraft";
    version = "0.18.0";
    hash = "sha256-55CVUSbsV7u6ZElYklhvXByUSJv8Zkk4EpK0tQB308k=";
    linuxHash = "sha256-0fEpr4wS8SULzBfbzbqsOAkAyROByEpK2m7ntICk2wY=";
  }
  {
    name = "SoundCraft";
    version = "0.19.0";
    hash = "sha256-lLZJUDtoxwsEjxLleOhZvuUcp9cY2wsC+VWgayipaW8=";
    linuxHash = "sha256-iaKb9Iwpnu5ZPXzWhLIchIPKKHq8GWZXrj+Vmh68GK0=";
  }
  {
    name = "CADCraft";
    version = "0.20.0";
    hash = "sha256-1VkMQJ5zyL7HK0XJfihQ4ntIHrUDg/ksfWw3nXCYy40=";
    linuxHash = "sha256-UAWDN6wl9UL87yyDQxg1dtDEIKocfdYjEQvtiZ4sSOk=";
  }
]
