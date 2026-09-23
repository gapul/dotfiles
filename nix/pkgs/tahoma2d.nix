# Tahoma2D: OpenToonz fork with native Apple Silicon builds. Replaces the opentoonz cask,
# whose only macOS build is x86_64 (Rosetta).
#
# There is no cask and no darwin build in nixpkgs, so the official portable dmg is repackaged.
# Portable mode keeps the "stuff" folder (profiles, config, library) inside the bundle and writes
# to it at runtime, which cannot work from the read-only store. The app only treats itself as
# portable when Contents/Resources/tahomastuff exists (tenv.cpp setWorkingDirectory), so the
# folder moves out to $out/share and SystemVar.ini — read from Contents/Resources on macOS —
# points at a writable stuffDir instead. That is what the .pkg installer's postinstall does too.
# hosts/darwin.nix seeds stuffDir from $out/share on activation.
{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
  stuffDir,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "tahoma2d";
  version = "1.6.3";

  src = fetchurl {
    url = "https://github.com/tahoma2d/tahoma2d/releases/download/v${finalAttrs.version}/Tahoma2D-portable-osx-silicon.dmg";
    hash = "sha256-IuqnVQ3Udz83ekdEjZjwGHPowAr9DOND3MSWBT4JiiQ=";
  };

  # hdiutil cannot attach inside the build sandbox; 7zz reads the HFS+ image.
  nativeBuildInputs = [ _7zz ];

  unpackPhase = ''
    runHook preUnpack
    7zz x -snld $src
    runHook postUnpack
  '';

  sourceRoot = "Tahoma2D";

  dontPatchShebangs = true;
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    res=Tahoma2D.app/Contents/Resources
    mkdir -p $out/Applications $out/share/tahoma2d
    mv $res/tahomastuff $out/share/tahoma2d/stuff
    substituteInPlace $res/SystemVar.ini \
      --replace-fail /Applications/Tahoma2D/Tahoma2D_stuff ${lib.escapeShellArg stuffDir}
    cp -R Tahoma2D.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "2D animation software based on OpenToonz";
    homepage = "https://tahoma2d.org";
    license = lib.licenses.bsd3;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
