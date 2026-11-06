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
    version = "0.21.0";
    hash = "sha256-qkOxhK6KKuI0C38lIqmWQx/+w1l+x2ttl3pEpsvXurE=";
    linuxHash = "sha256-MRXlbMZG2601QeObYyO4okMY/uYZTXhN320GX3tdLTc=";
  }
  {
    name = "VectorCraft";
    version = "0.22.0";
    hash = "sha256-KerOMfDxRy+H011/kLsJuDdEE8SsGt+x9TdDHcFI+2A=";
    linuxHash = "sha256-boEqksrsTboj/XRzT6IKMniG7yBCe1Xy+If+kzSgkz8=";
  }
  {
    name = "FilmCraft";
    version = "0.18.0";
    hash = "sha256-Lzm73CbXgpaTBbNQkCUBUHNKPpmjebMrUMRjc6ZPTlI=";
    linuxHash = "sha256-AXnwWyDbhVv9Pe+RNs5g3uWfItLcv88j5KYlbgwVOwU=";
  }
  {
    name = "LightCraft";
    version = "0.19.0";
    hash = "sha256-yZdzT4tzZRhSDvOksxmtJcQM8DoHR7nj2rbvEBepaZo=";
    linuxHash = "sha256-lIXWS9vpjG2vutDqeqwPpJQw0KAIuaZrpD3+d7dVUok=";
  }
  {
    name = "PdfCraft";
    version = "0.19.0";
    hash = "sha256-i0HZB7GgMLS6jfA7Xrlp9wkPj0Hs4jvLeZB38gihDJY=";
    linuxHash = "sha256-NleqQP4UbUr0D6sFB8l/buLGzlupk4VnGUQ5vjM1uos=";
  }
  {
    name = "EffectCraft";
    version = "0.22.0";
    hash = "sha256-vXG4WfXjhaUud2BMTaGQaeX57pT5m7nYntO2PsjDhdQ=";
    linuxHash = "sha256-X+mwrldGrCm2H33qEL1ntx6ZbB4BiIJMT4GpZiPDvuk=";
  }
  {
    name = "DesignCraft";
    version = "0.18.0";
    hash = "sha256-DCRIc4mxyHEMROAF01Ld+ZGa2q7894pTvFIuoiX/4iU=";
    linuxHash = "sha256-U5h8tmvn3pOFTtVwAEJ/vhwHKgQnvIy69QH/NnLVQyw=";
  }
  {
    name = "WordCraft";
    version = "0.16.0";
    hash = "sha256-QHy3uhSVQ3gQvwZteZFB4KtDJUBghFVr4UIjaL0Is3c=";
    linuxHash = "sha256-MluX8Vu/UyYooxdqnBcUinF18+Txm5MT3jI6tRNgl1I=";
  }
  {
    name = "GridCraft";
    version = "0.17.0";
    hash = "sha256-NbpgbkSNv14Q25UINUWTRopO850pdkThLBeeVbcv8Kc=";
    linuxHash = "sha256-FOk3RVW8bS2cW8QbsxFQvGoctrToPVq0Fj/V12EbBhg=";
  }
  {
    name = "DeckCraft";
    version = "0.16.0";
    hash = "sha256-6c8O7mk4ZqNZ5pBavLMLtojbr1fWBBRdVmjxhJuLokc=";
    linuxHash = "sha256-7tVysvYjldD1z+JGpygYllHpXk7N9MPgrYe3ejgx4IY=";
  }
  {
    name = "SoundCraft";
    version = "0.18.0";
    hash = "sha256-yTziBzDC41vSscPc6NKI61As9GQP6wJXNL18vmGRVIc=";
    linuxHash = "sha256-M40f5yuWkqXZn/Q1UD31jIU/W5bC6VsoIdiD8x+LWmY=";
  }
  {
    name = "CADCraft";
    version = "0.18.0";
    hash = "sha256-5Z2YYV/OzJ1e8GUMY0hiKdfSqiKRT7jRBQpdBxMp+ck=";
    linuxHash = "sha256-DVtSKvz6IMfliIfCCS+1rVMi65DB2pgGHmG346zRvtU=";
  }
]
