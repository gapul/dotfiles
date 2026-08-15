# A URL-scheme handler that forwards MakerWorld's "Open in Bambu Studio" links to OrcaSlicer.
# See main.m for why this exists and why Orca's own bundle is left alone.
#
# The bundle lands in $out/libexec rather than $out/Applications on purpose. Anything under
# Applications/ gets symlinked into "/Applications/Nix Apps" by nix-darwin (or "~/Applications/
# Home Manager Apps" by home-manager), which would put a launcher for it in Launchpad. This has
# no UI at all, so it is registered with LaunchServices straight from the store instead — see the
# activation hook in home/darwin.nix.
{ stdenv }:
stdenv.mkDerivation {
  pname = "orca-url-shim";
  version = "1.0";

  src = ./.;

  buildPhase = ''
    runHook preBuild
    clang -fobjc-arc -O2 -framework AppKit -framework Foundation main.m -o OrcaURLShim
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./OrcaURLShim --self-test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    app=$out/libexec/OrcaURLShim.app
    install -Dm755 OrcaURLShim $app/Contents/MacOS/OrcaURLShim
    install -Dm644 ${./Info.plist} $app/Contents/Info.plist
    printf 'APPL????' > $app/Contents/PkgInfo
    runHook postInstall
  '';

  meta = {
    description = "Forwards bambustudio:// URLs (MakerWorld one-click print) to OrcaSlicer";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
}
