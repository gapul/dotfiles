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
    version = "0.17.0";
    hash = "sha256-bgkDFyp0QM5OcQAvVYW6Tv9Yj6P8mbeM2YERgMq9W4A=";
    linuxHash = "sha256-Uln5xCjI7jR4w1UA7OmHE1Ycr8BQ5MnrNUpQUPNusrg=";
  }
  {
    name = "VectorCraft";
    version = "0.18.0";
    hash = "sha256-boc/s56usujsXqgrrTZnB9buTzCAthV6YlxS73RjOHQ=";
    linuxHash = "sha256-dpSLUO943Ugqbs4G8QtwR5N7vAwF9c9rxD2IsH902CY=";
  }
  {
    name = "FilmCraft";
    version = "0.14.0";
    hash = "sha256-n4dWT4P1XZ3qMs7rc6o8t0sVrsBTR90+Fj/Qpqvvayc=";
    linuxHash = "sha256-0qohPMCKvSHgWrURp4zDjxV8ryImmS8/yKXgSWo/fn0=";
  }
  {
    name = "LightCraft";
    version = "0.15.0";
    hash = "sha256-F1weaBh9kc+QAzqTAV+0y0UEVXVbePQeOUqeoJ53zek=";
    linuxHash = "sha256-CxrN78CFurszS5rdKQ3RpptQ6W772tLsFdRL1tZL/T0=";
  }
  {
    name = "PdfCraft";
    version = "0.15.0";
    hash = "sha256-wST8LtUSdllD+y6OdkvBTAedxbfXpUOczbNAHfeP1HI=";
    linuxHash = "sha256-sWehjGCnsynwWlu/l+Mtxniq0/jVhm2OQ3j/JCc/gxM=";
  }
  {
    name = "EffectCraft";
    version = "0.18.0";
    hash = "sha256-eaDCSmRAGOs5tyLt21oVo0KAyGhWFx9qZBWjVBsYIAQ=";
    linuxHash = "sha256-lNHYVpHVS6V/qG4Ehy+8xCbDPRvTZPH8l2sfYHNEiAs=";
  }
  {
    name = "DesignCraft";
    version = "0.14.0";
    hash = "sha256-k5L7Vj3gbaLspIeRpA+BL3IRA2lzYgFWWbP/dXfnsIE=";
    linuxHash = "sha256-Jch751nTWoHKROH2Je1DBLFuWqtqA6EFG8pJioG/xUc=";
  }
  {
    name = "WordCraft";
    version = "0.12.0";
    hash = "sha256-JETrnKJ1X0ZVxV6X2d5jh28zihWIqzXpEqx284zqdwk=";
    linuxHash = "sha256-zZq9DuehG5ha8cFXFlMzLJYHfl3MSLXhh7VcgvR1oz4=";
  }
  {
    name = "GridCraft";
    version = "0.13.0";
    hash = "sha256-Z7agI7Rl7fhe9aMJ1JprAKCF4+o9yd3cAGCZazhRUWg=";
    linuxHash = "sha256-IMbFbsH/1rvP/ubN7ljPa1yt0vSgSkNg3XzGTVOtl+U=";
  }
  {
    name = "DeckCraft";
    version = "0.12.0";
    hash = "sha256-/rflRUPBNrNJR5dGtgd5zFvz5diz0Vg4FW7RYAXSU9U=";
    linuxHash = "sha256-SkENPKpCPoc9Dcq1HJjgZYj1W9/PA+nB6RQJqGwI3j4=";
  }
  {
    name = "SoundCraft";
    version = "0.14.0";
    hash = "sha256-k3fhZGcOy3akYQhorCT3gEQV2CzwAWwn8kzDzFuqQd8=";
    linuxHash = "sha256-L4NQP+2mqiyNS8EsRPVxQixDifxmSpK77QktK/HVAK0=";
  }
  {
    name = "CADCraft";
    version = "0.14.0";
    hash = "sha256-BarhzDN0XAzUFx504Flx1iWymIS7SeAHAxpCrhrcAtI=";
    linuxHash = "sha256-lQZ8hJ+CMFZIJJKZu4bmRbcwJ1qoxfGZZdgZkPg66ps=";
  }
]
