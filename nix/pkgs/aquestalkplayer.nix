# AquesTalkPlayer - Aquest's player for their AquesTalk speech engines, which
# is where the "yukkuri" voices come from. Declared here for the headless side
# of it: `aquestalkplayer -P <preset> -F in.txt -W out.wav` synthesises without
# opening a window, so yukkuri narration can be produced on macOS without
# Windows, Yukkuri MovieMaker or AviUtl. The GUI is still needed once, to save
# the presets that -P then selects by name (れいむ / まりさ ship with it).
#
# Speed, pitch and voice are GUI-only; the CLI takes just -P/-T/-F/-W.
#
# The download is behind a Cloudflare Turnstile challenge, so fetchurl cannot
# reach it - the direct URL answers 403 to anything but a browser that solved
# the challenge. Hence requireFile: the dmg goes into the store by hand, once
# per version bump, which for this app is close to never (1.0.1 is from
# 2025-08-29).
#
#   nix-store --add-fixed sha256 ~/Downloads/AquesTalkPlayer-1.0.1.dmg
#
# Free for personal, non-commercial use only. Monetised output needs a
# commercial licence from Aquest.
{
  lib,
  stdenvNoCC,
  requireFile,
  _7zz,
}:
let
  version = "1.0.1";
  app = "AquesTalkPlayer.app";
in
stdenvNoCC.mkDerivation {
  pname = "aquestalkplayer";
  inherit version;

  src = requireFile {
    name = "AquesTalkPlayer-${version}.dmg";
    hash = "sha256-BYmRqzivD+23Dz1LM7ldTku2qc+Kn0f1ucTRpLUnGcc=";
    url = "https://www.a-quest.com/products/aquestalkplayer.html#download";
  };

  # Same as vroid-studio and aivisspeech: the dmg is APFS, which undmg cannot
  # read and hdiutil cannot attach inside the build sandbox. 7zz handles it.
  nativeBuildInputs = [ _7zz ];

  unpackPhase = ''
    runHook preUnpack
    7zz x -snld $src
    runHook postUnpack
  '';

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications $out/bin
    cp -R "${app}" "$out/Applications/${app}"

    # Not a symlink to the bundle executable: invoked through one the app fails
    # to find its own bundle and exits 15. Nor makeWrapper, which sets argv[0]
    # to the wrapper for the same effect. A plain exec of the real path works.
    printf '#!/bin/sh\nexec "%s" "$@"\n' \
      "$out/Applications/${app}/Contents/MacOS/AquesTalkPlayer" \
      > $out/bin/aquestalkplayer
    chmod +x $out/bin/aquestalkplayer
    runHook postInstall
  '';

  postInstall = ''
    exe="$out/Applications/${app}/Contents/MacOS/AquesTalkPlayer"
    if [ ! -x "$exe" ]; then
      echo "expected executable missing: $exe"
      exit 1
    fi
  '';

  meta = {
    description = "AquesTalk speech player (yukkuri voices), with a headless wav-out CLI";
    homepage = "https://www.a-quest.com/products/aquestalkplayer.html";
    license = lib.licenses.unfree; # free for personal non-commercial use
    platforms = [ "aarch64-darwin" ];
    mainProgram = "aquestalkplayer";
  };
}
