# Headitude - reads AirPods head orientation and forwards it over OSC.
#
# CoreMotion's CMHeadphoneMotionManager exposes the IMU in AirPods Pro / Max /
# 3rd gen (and Beats Fit Pro) to macOS from Sonoma 14.0 on, and this is the one
# app that turns that into OSC without going through an iOS device. Used as a
# head-rotation source for VTubing: it keeps working while the face is out of
# frame, which camera tracking cannot.
#
# Not in nixpkgs and no Homebrew cask, so the official release zip is
# repackaged. Upstream calls it early stage - v1.0 (2023-11) is still the only
# release. Orientation only, no position, and it needs the calibration routine
# in the app because it cannot know how the AirPods sit in the ear.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
let
  version = "1.0";
  app = "Headitude.app";
in
stdenvNoCC.mkDerivation {
  pname = "headitude";
  inherit version;

  src = fetchurl {
    url = "https://github.com/DanielRudrich/Headitude/releases/download/v${version}/Headitude.zip";
    hash = "sha256-EAn6rJ4jMdcMuMJQwVyhUYRAvhmTepiFazNp+tIAH10=";
  };

  nativeBuildInputs = [ unzip ];

  # The archive is a plain zip holding the bundle plus the __MACOSX sidecar
  # directory that macOS' own compressor adds; the latter is dropped.
  unpackPhase = ''
    runHook preUnpack
    unzip -q $src -x '__MACOSX/*'
    runHook postUnpack
  '';

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R "${app}" "$out/Applications/${app}"
    runHook postInstall
  '';

  # Unlike the VRoid dmg, the signature survives unpacking here: this bundle
  # carries a modern _CodeSignature and nothing hangs off extended attributes,
  # so `spctl -a -t exec` still reports "Notarized Developer ID" after unzip.
  # That matters because the app asks for the Motion & Fitness TCC grant, and
  # TCC keys those to the signature.
  postInstall = ''
    exe="$out/Applications/${app}/Contents/MacOS/Headitude"
    if [ ! -x "$exe" ]; then
      echo "expected executable missing: $exe"
      exit 1
    fi
  '';

  meta = {
    description = "Forwards AirPods head orientation over OSC";
    homepage = "https://github.com/DanielRudrich/Headitude";
    license = lib.licenses.mit;
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
}
