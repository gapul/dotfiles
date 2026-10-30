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
# The toolchain's lldb does not load (it wants Ubuntu's libedit.so.2 and ncurses symbol
# versions); xtool's build, sign and install do not use it.
let
  version = "1.24.0";
  swiftVersion = "6.3.3";

  xtool = appimageTools.extract {
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
  # The AppImage's usual libraries (what wrapType2 would give xtool), plus swift.org's list of
  # Ubuntu 24.04 dependencies for the toolchain.
  inherit (appimageTools.defaultFhsEnvArgs) multiPkgs;
  targetPkgs =
    pkgs:
    appimageTools.defaultFhsEnvArgs.targetPkgs pkgs
    ++ [
      swiftToolchain
      pkgs.binutils
      pkgs.curl
      # Unwrapped GCC: swift.org's clang links with crtbeginS.o / libgcc from
      # /usr/lib64/gcc/<triple>/<version>, the layout Ubuntu's libgcc-13-dev gives it.
      pkgs.stdenv.cc.cc
      pkgs.stdenv.cc.cc.lib
      pkgs.git
      pkgs.glibc.dev
      pkgs.gnupg
      pkgs.libedit
      pkgs.libuuid
      pkgs.libxml2_13 # libxml2.so.2, as on Ubuntu 24.04 (2.14+ is .so.16)
      pkgs.ncurses
      pkgs.pkg-config
      pkgs.python312 # lldb links libpython3.12
      pkgs.sqlite
      pkgs.tzdata
      pkgs.unzip
      pkgs.zip # xtool packs the .ipa with it
      pkgs.z3
      pkgs.zlib
    ];
  # nixpkgs' libncurses.so.6 / libtinfo.so.6 are symlinks to libncursesw, so ld.so.cache has no
  # entry under the names the toolchain asks for; let the loader look in the directory itself.
  profile = ''
    export LD_LIBRARY_PATH=/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  '';
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
