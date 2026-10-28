{
  lib,
  appimageTools,
  fetchurl,
}:
# Cross-platform Xcode replacement: builds, signs and installs iOS apps from Linux.
# Not in nixpkgs. xtool shells out to `swift` from PATH and builds against a Darwin Swift SDK it
# extracts from Xcode (`xtool sdk install <Xcode.app|Xcode.xip>`), stored under ~/.swiftpm.
# The SDK's Swift has to match the toolchain on PATH (Xcode 26.6 and nixpkgs both ship 6.3.3).
appimageTools.wrapType2 rec {
  pname = "xtool";
  version = "1.24.0";
  src = fetchurl {
    url = "https://github.com/xtool-org/xtool/releases/download/${version}/xtool-x86_64.AppImage";
    hash = "sha256-2/2dchbwd8hMFxtojEFzw3wjyna/f9GF0amuilPatZ8=";
  };
  meta = {
    description = "Cross-platform Xcode replacement for building and installing iOS apps";
    homepage = "https://github.com/xtool-org/xtool";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "xtool";
  };
}
