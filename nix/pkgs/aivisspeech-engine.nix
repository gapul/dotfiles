# AivisSpeech Engine - headless TTS engine (Style-Bert-VITS2 based, VOICEVOX
# Engine API-compatible fork).
#
# Not in nixpkgs and there is no Homebrew cask. Only the engine is declared:
# the desktop app is not needed because everything drives the engine over its
# HTTP API (port 10101), same as VOICEVOX's vv-engine. Voice models (.aivmx)
# are runtime-mutable user data, downloaded by the engine itself into
# ~/.local/share/AivisSpeech-Engine/Models on first use, so they are managed
# imperatively - same call as the AI model assets on the mini.
{
  lib,
  stdenvNoCC,
  fetchurl,
  p7zip,
  makeWrapper,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "aivisspeech-engine";
  version = "1.2.0";

  # GitHub splits the release into .7z.001 parts; 1.2.0 fits in a single part.
  # If a future version grows a .002, fetch both and list them in srcs.
  src = fetchurl {
    url = "https://github.com/Aivis-Project/AivisSpeech-Engine/releases/download/${finalAttrs.version}/AivisSpeech-Engine-macOS-arm64-${finalAttrs.version}.7z.001";
    hash = "sha256-WBp/NK+yxTQ/+LJ9bYiFkIM3WGhgdlfelfrVBpORhd8=";
  };

  nativeBuildInputs = [
    p7zip
    makeWrapper
  ];

  unpackPhase = ''
    runHook preUnpack
    7z x $src
    runHook postUnpack
  '';

  sourceRoot = ".";

  # The binary resolves engine_internal/ and resources/ relative to its own
  # location, so the whole tree is kept together and exposed via a wrapper
  # (a bare symlink would break that resolution).
  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec $out/bin
    cp -R macOS-arm64 $out/libexec/aivisspeech-engine
    makeWrapper $out/libexec/aivisspeech-engine/run $out/bin/aivisspeech-engine
    runHook postInstall
  '';

  postInstall = ''
    if [ ! -x "$out/libexec/aivisspeech-engine/run" ]; then
      echo "expected engine executable missing"
      exit 1
    fi
  '';

  meta = {
    description = "TTS engine of AivisSpeech (VOICEVOX Engine compatible API)";
    homepage = "https://github.com/Aivis-Project/AivisSpeech-Engine";
    license = lib.licenses.lgpl3Only;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "aivisspeech-engine";
  };
})
