# OmniWM: the tiling window manager this machine runs on.
#
# Packaged here rather than taken from barutsrb/tap for one reason: version control. As a cask it
# had no pin — casks cannot be `brew pin`ed — so `just maintain` (which trusts the taps and then
# runs `brew upgrade --cask --greedy`) pulled 0.5.9 → 0.6.3 unattended on 2026-08-29, and 0.6.3's
# two new settings keys made it declare the whole settings.toml corrupt and write defaults back
# over the copy in this repo. Every hotkey was gone before anyone noticed. Here the version is
# whatever flake.lock says, so an upgrade is something you do rather than something that happens.
#
# The signed release artifact is fetched rather than built, so the Developer ID signature
# (Oliver Nikolic, VF8LDJRGFM) survives and the Accessibility grant with it — the distinction that
# made sketchybar unmovable (nixpkgs builds that one from source, so it is ad-hoc signed and TCC
# will not hold). See pkgs/keebmouse.nix for the same shape.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "omniwm";
  version = "0.6.4";

  src = fetchurl {
    url = "https://github.com/BarutSRB/OmniWM/releases/download/v${finalAttrs.version}/OmniWM-v${finalAttrs.version}.zip";
    hash = "sha256-myv1TSDWf1NicAMuBiUXbAbG4DuIl93wJVWNlIM55ec=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";

  dontPatchShebangs = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    # unzip materialises AppleDouble sidecars that the signature never sealed, which alone makes
    # `codesign -v` fail — see pkgs/keebmouse.nix for the full note.
    find . -name '._*' -delete
    find . -name '.DS_Store' -delete
    mkdir -p $out/Applications
    cp -R OmniWM.app $out/Applications/
    # omniwmctl ships inside the bundle and the cask symlinked it onto PATH; keep that. A symlink
    # rather than a copy so the CLI and the running app are always the same build — a cask upgrade
    # used to leave them out of step, and the resulting protocol_mismatch is silent (the wallpaper
    # and status bar hooks just stop).
    mkdir -p $out/bin
    ln -s $out/Applications/OmniWM.app/Contents/MacOS/omniwmctl $out/bin/omniwmctl
    runHook postInstall
  '';

  meta = {
    description = "Tiling window manager for macOS with Niri-inspired column-based layout";
    homepage = "https://github.com/BarutSRB/OmniWM";
    platforms = [ "aarch64-darwin" ];
    mainProgram = "omniwmctl";
  };
})
