{
  lib,
  stdenvNoCC,
  appimageTools,
  buildFHSEnv,
  fetchurl,
}:
# Cross-platform Xcode replacement: builds, signs and installs iOS apps from Linux.
# Not in nixpkgs. xtool shells out to `swift` from PATH and builds against a Darwin Swift SDK it
# extracts from Xcode (`xtool sdk install <Xcode.app|Xcode.xip>`, kept in ~/.config/swiftpm).
#
# nixpkgs' swift does not work here: its clang is cc-wrapped, which adds glibc's
# -dynamic-linker to the arm64-apple-ios link and ld64.lld rejects it (2026-10-28). So xtool runs
# in an FHS env with swift.org's own Ubuntu toolchain. The SDK's Swift has to match it: Xcode 26.6
# ships 6.3.3. Bump `swiftVersion` together with the Xcode the SDK is built from.
let
  version = "1.24.0";
  swiftVersion = "6.3.3";

  xtool = appimageTools.extractType2 {
    pname = "xtool";
    inherit version;
    src = fetchurl {
      url = "https://github.com/xtool-org/xtool/releases/download/${version}/xtool-x86_64.AppImage";
      hash = "sha256-2/2dchbwd8hMFxtojEFzw3wjyna/f9GF0amuilPatZ8=";
    };
  };

  # Signed by "Swift 6.x Release Signing Key" (EF80A866B47A981F), checked once when pinned.
  swiftToolchain = stdenvNoCC.mkDerivation {
    pname = "swift-toolchain-ubuntu";
    version = swiftVersion;
    src = fetchurl {
      url = "https://download.swift.org/swift-${swiftVersion}-release/ubuntu2404/swift-${swiftVersion}-RELEASE/swift-${swiftVersion}-RELEASE-ubuntu24.04.tar.gz";
      hash = "sha256-2oJypf3czWWxUp7Q5S4EUm4urdQjfVjWIg7+uXPGzRk=";
    };
    # Prebuilt for an FHS layout; patching would break the toolchain's relative lookups.
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -a usr/. "$out/"
      runHook postInstall
    '';
  };
in
buildFHSEnv {
  pname = "xtool";
  inherit version;
  # swift.org's list of Ubuntu 24.04 dependencies.
  targetPkgs = pkgs: [
    swiftToolchain
    pkgs.binutils
    pkgs.curl
    pkgs.gcc
    pkgs.git
    pkgs.glibc.dev
    pkgs.gnupg
    pkgs.libedit
    pkgs.libuuid
    pkgs.libxml2
    pkgs.ncurses
    pkgs.pkg-config
    pkgs.python3
    pkgs.sqlite
    pkgs.tzdata
    pkgs.unzip
    pkgs.z3
    pkgs.zlib
  ];
  runScript = "${xtool}/AppRun";
  meta = {
    description = "Cross-platform Xcode replacement for building and installing iOS apps";
    homepage = "https://github.com/xtool-org/xtool";
    license = with lib.licenses; [
      mit # xtool
      asl20 # Swift toolchain
    ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "xtool";
  };
}
