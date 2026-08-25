# AivisSpeech - desktop editor app for the AivisSpeech TTS (VOICEVOX editor
# fork on Style-Bert-VITS2 voices).
#
# Not in nixpkgs and there is no Homebrew cask, so the official dmg is
# repackaged like vroid-studio. The app bundles its own copy of the engine,
# but the declared headless engine (pkgs/aivisspeech-engine.nix, newer) stays
# the one scripts use; both share the model directory under
# ~/.local/share/AivisSpeech-Engine, so voices installed once work in both.
# App and engine version numbers are independent upstream.
{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:
let
  version = "1.0.0";
  app = "AivisSpeech.app";
in
stdenvNoCC.mkDerivation {
  pname = "aivisspeech";
  inherit version;

  src = fetchurl {
    url = "https://github.com/Aivis-Project/AivisSpeech/releases/download/${version}/AivisSpeech-macOS-arm64-${version}.dmg";
    hash = "sha256-+DIP/FRNzv4qPPb32la4HINCoIt6rV5r7lWYQXtuw5c=";
  };

  # Same reason as vroid-studio: the dmg is APFS, which undmg cannot read and
  # hdiutil cannot attach inside the sandbox; 7zz handles it.
  nativeBuildInputs = [ _7zz ];

  unpackPhase = ''
    runHook preUnpack
    7zz x -snld $src
    runHook postUnpack
  '';

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R "${app}" "$out/Applications/${app}"
    runHook postInstall
  '';

  postInstall = ''
    exe="$out/Applications/${app}/Contents/MacOS/AivisSpeech"
    if [ ! -x "$exe" ]; then
      echo "expected executable missing: $exe"
      exit 1
    fi
  '';

  meta = {
    description = "Desktop editor for AivisSpeech TTS (VOICEVOX editor fork)";
    homepage = "https://github.com/Aivis-Project/AivisSpeech";
    license = lib.licenses.lgpl3Only;
    platforms = [ "aarch64-darwin" ];
  };
}
