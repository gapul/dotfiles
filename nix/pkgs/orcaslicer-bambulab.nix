# OrcaSlicer-bambulab (FULU Foundation): the Orca fork that can still start a
# print on a Bambu printer.
#
# Bambu's Authorization Control closed the path third-party slicers used. File
# transfer over FTPS still works, but the MQTT `project_file` command is
# acknowledged and then ignored - verified here against an A1 mini, where the
# echo comes back and gcode_state never leaves FINISH. Upstream Orca declined to
# route through Bambu Connect, so pkgs.brewCasks.orcaslicer can only slice and
# export. This fork replaces the proprietary bambu_networking plugin with its own
# implementation and sends directly.
#
# Paweł Jarczak published the original fork, withdrew it under a Bambu cease and
# desist, and Software Freedom Conservancy then found Bambu in violation of
# AGPLv3 and took over maintenance as `baltobu`. The FULU Foundation build is
# packaged here because it is the branch that ships macOS binaries; baltobu is
# source-only so far. Watch <https://f.sfconservancy.org/baltobu> and move over
# once it publishes builds - that is the canonical line.
#
# Installed next to the cask rather than replacing it: the fork tracks 2.4.0-dev
# while the cask is on 2.4.2, so it gets its own bundle name and its own datadir.
# Letting the older build open the newer config directory downgrades the presets
# in place, and those hold the printer bindings and access codes.
{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:
let
  version = "1.0.0";
  app = "OrcaSlicer.app";
  target = "OrcaSlicer Bambu.app";
in
stdenvNoCC.mkDerivation {
  pname = "orcaslicer-bambulab";
  inherit version;

  src = fetchurl {
    url = "https://github.com/FULU-Foundation/OrcaSlicer-bambulab/releases/download/v${version}/OrcaSlicer_Mac_universal_V2.4.0-dev.dmg";
    hash = "sha256-cZR5WekYTwZG3oPbkegTem76YKJphrrrTnw+7pveNhc=";
  };

  # Same reason as pkgs/vroid-studio.nix: the dmg is APFS, which undmg cannot
  # read, and hdiutil cannot attach an image inside the build sandbox.
  nativeBuildInputs = [ _7zz ];

  unpackPhase = ''
    runHook preUnpack
    7zz x -snld $src
    runHook postUnpack
  '';

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R "${app}" "$out/Applications/${target}"

    # Give the fork a datadir of its own. The launcher is the only place this can
    # happen: macOS passes no arguments into an .app, and Orca takes the
    # directory only as --datadir. So the real binary moves aside and a shell
    # script takes its place at CFBundleExecutable. Nothing is lost by doing so -
    # 7zz cannot restore the signature's extended attributes, so the bundle is
    # already unsigned by the time it is installed (same as vroid-studio, and
    # store paths never carry com.apple.quarantine, so Gatekeeper is not asked).
    real="$out/Applications/${target}/Contents/MacOS/OrcaSlicer"
    mv "$real" "$real-bin"
    printf '#!/bin/sh\nexec "$(dirname "$0")/OrcaSlicer-bin" --datadir "$HOME/Library/Application Support/OrcaSlicerBambu" "$@"\n' > "$real"
    chmod +x "$real"
    runHook postInstall
  '';

  meta = {
    description = "Orca Slicer fork that sends print jobs to Bambu printers without Bambu Connect";
    homepage = "https://github.com/FULU-Foundation/OrcaSlicer-bambulab";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
