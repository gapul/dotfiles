# Move heavy rendering to the macmini.
#
# It lives on this machine not because it has spare capacity, but so the main Mac isn't tied
# up. An export running while editing or writing makes the machine useless the whole time.
#
# Measured (2026-09-01): memory is 68% free, and the only constant consumer is the manabi
# next-server (22%). The MLX stuff only runs when called, so it competes with exports only
# when both are hit at the same time.
#
# ## What can and can't be declared
#
#   blender  — in nixpkgs with darwin support. `blender -b file.blend -a` renders headless
#   ffmpeg   — already installed. Hardware encoding works via the M4's VideoToolbox
#
#   DaVinci  — the nixpkgs package is x86_64-linux only (verified). Using it on darwin means
#              installing Blackmagic's dmg by hand, outside the declaration
#   Adobe    — the Creative Cloud installer is declared as a brew cask. After Effects itself and
#              its updates are managed by Creative Cloud, so beyond that it's outside Nix
#
# The Adobe policy is to install After Effects only (2026-09-01). The goal is aerender, a
# command that renders comps headless. That is the only reason to have it on the macmini.
#
# No Premiere. The only way to trigger exports from outside is Media Encoder's watch folder,
# which assumes the app is running, so it doesn't suit this headless machine.
# DaVinci is skipped for the same reason (plus the nixpkgs package is x86_64-linux only).
#
# The Creative Cloud installer is declared in hosts/macmini.nix. Sign-in credentials can be
# entered via the ask MCP's allowlisted native helper, but screen transitions and extra
# authentication use Screen Sharing:
#
#   1. Launch Creative Cloud and sign in via MCP
#   2. Complete the extra authentication over Screen Sharing
#   3. Install After Effects only (not Premiere)
#
# Once installed, aerender lands here:
#   /Applications/Adobe After Effects <year>/aerender
#
# The main Mac's `macmini-render after-effects` detects this path dynamically. To avoid missing
# media, it temporarily transfers the whole directory gathered by After Effects' Collect Files,
# and deletes it when done.
{
  config,
  pkgs,
  ...
}:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  # Android SDK for compile work and an arm64 Google Play emulator. The emulator is used for
  # compatibility testing of official Android apps on the Mac mini; keep its licensed Google
  # system image local to this host composition.
  androidEnv = pkgs.callPackage "${pkgs.path}/pkgs/development/mobile/androidenv" {
    licenseAccepted = true;
  };
  androidSdk =
    (androidEnv.composeAndroidPackages {
      # Flutter 3.41 currently checks for API 36 and retains a compatibility check for 28.0.3.
      platformVersions = [
        "35"
        "36"
      ];
      buildToolsVersions = [
        "28.0.3"
        "35.0.0"
        "36.0.0"
      ];
      # Flutter plugins with Android native code request this through Gradle. Keep it inside the
      # immutable SDK because Gradle cannot install missing SDK components into the Nix store.
      cmakeVersions = [ "3.22.1" ];
      includeEmulator = true;
      includeSystemImages = true;
      systemImageTypes = [ "google_apis_playstore" ];
      abiVersions = [ "arm64-v8a" ];
      # Flutter 3.41's Android plugins request this exact side-by-side NDK. A Nix SDK is
      # read-only, so Gradle cannot lazily install it during the first APK build.
      includeNDK = true;
      ndkVersions = [ "28.2.13676358" ];
    }).androidsdk;
  jdk = pkgs.jdk21_headless;
in
{
  home.packages = with pkgs; [
    # Blender is installed as a brew cask, not via nix (hosts/macmini.nix). See the comment
    # there for why: the nixpkgs build's manifold dependency fails its tests on the macmini, and
    # there's no aarch64-darwin cache, so it would be built from source.
    #
    # For headless renders, call the binary inside the .app:
    #   /Applications/Blender.app/Contents/MacOS/Blender -b scene.blend -a

    # Post-export conversion and re-encoding. Jobs that don't need the editing app end here.
    # For the M4 hardware encoder use -c:v hevc_videotoolbox / h264_videotoolbox.
    # The footage is HLG HDR, so going to SDR without an explicit color conversion looks washed out.
    ffmpeg-full

    # General-purpose native build worker. Project-specific flakes still win when present;
    # these tools cover ordinary Cargo/CMake/Node repositories and keep compilation off the
    # interactive MacBook. rustup respects each repository's rust-toolchain.toml.
    rustup
    cmake
    ninja
    ccache
    pkg-config
    gnumake
    bun
    go

    # Mobile/WebAssembly builds. Signing, Simulator and physical-device deployment still happen
    # on the workstation; the mini produces unsigned archives/APKs and other deterministic output.
    pkgs.flutter
    androidSdk
    jdk
    pkgs.gradle
    pkgs.cocoapods
    pkgs.xcodegen
    pkgs.swiftformat
    pkgs.swiftlint
    pkgs.wasm-pack
    pkgs.protobuf
  ];

  home.sessionVariables = {
    ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
    ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
    ANDROID_AVD_HOME = "${config.xdg.configHome}/.android/avd";
    JAVA_HOME = jdk.home;
  };

  home.file = {
    ".local/bin/macmini-compile-worker".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/bin/macmini-compile-worker";
    ".local/bin/macmini-render-worker".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/bin/macmini-render-worker";
  };
}
