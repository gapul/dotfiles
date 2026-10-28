# Lan Mouse for macOS: one mouse and keyboard across the Mac and nixos-laptop (Linux uses
# nixpkgs' lan-mouse).
#
# Fetched rather than built: upstream's bundle is only ad-hoc signed, so Accessibility is tied to
# its cdhash. The release artifact keeps one cdhash per version, while a nixpkgs source build
# would get a new one on every flake.lock bump and lose the grant each time (the sketchybar
# lesson). Expect to re-grant Accessibility once per version bump. No cask exists.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "lan-mouse";
  version = "0.11.0";

  src = fetchurl {
    url = "https://github.com/feschber/lan-mouse/releases/download/v${finalAttrs.version}/lan-mouse-macos-arm64.zip";
    hash = "sha256-X/mWXQW+fxJbHXW55yWdh07JiqCGzkABJSK8JUBlAKk=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";

  # Touching the bundle would change the cdhash this package exists to keep.
  dontPatchShebangs = true;
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    # unzip writes AppleDouble sidecars out as files the signature never sealed (pkgs/keebmouse.nix).
    find . -name '._*' -delete
    find . -name '.DS_Store' -delete
    mkdir -p $out/Applications
    cp -R "Lan Mouse.app" $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "Mouse and keyboard sharing over the LAN";
    homepage = "https://github.com/feschber/lan-mouse";
    license = lib.licenses.gpl3Only;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
