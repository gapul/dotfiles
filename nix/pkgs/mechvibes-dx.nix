# MechvibesDX - mechanical keyboard sound simulator (successor to Mechvibes).
#
# Not in nixpkgs, and the upstream macOS DMG cannot be used: it is built against
# rdev 0.5.3 from crates.io, whose macOS keyboard handler calls Text Input
# Services from rdev's event-tap thread. macOS 26 made those calls assert on the
# main queue, so the released app dies with SIGTRAP on the FIRST keypress. See
# the postPatch below - upstream rdev fixed this on main (b7e201b, is_main_thread
# + a main-queue hop) but has not cut a release since 0.5.3 in 2023.
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  imagemagick,
  libicns,
}:
let
  version = "0.8.1";
  appName = "MechvibesDX";
in
rustPlatform.buildRustPackage {
  pname = "mechvibes-dx";
  inherit version;

  src = fetchFromGitHub {
    owner = "hainguyents13";
    repo = "mechvibes-dx";
    tag = "v${version}";
    hash = "sha256-UV/iBgC9GGaoP+ee3bXE4U6hv2Ywpp4+cyKFVevpQOw=";
  };

  cargoHash = "sha256-xr+mOzcdqM/MON29WcBG6nbQ4DgtL50zt4b7tozs9Ho=";

  nativeBuildInputs = [
    imagemagick # resize icon.png into the sizes png2icns accepts
    libicns # png2icns, standing in for the runner's iconutil
  ];

  # Drop rdev's per-keystroke key-name lookup instead of taking upstream main's
  # main-queue hop. MechvibesDX never reads Event.name (input_listener.rs only
  # matches on map_key_to_code), so the hop would pay a synchronous dispatch to
  # the UI thread on every keypress for a value that is thrown away - and a busy
  # UI thread would then stall the event tap, i.e. the whole system's input.
  # Returning None off-main costs nothing and cannot stall.
  #
  # Editing a vendored crate is safe here because fetchCargoVendor writes
  # `"files": {}` in .cargo-checksum.json, so cargo verifies no per-file hashes.
  # Drop this whole block once rdev releases > 0.5.3 and upstream bumps it.
  postPatch = ''
    substituteInPlace $cargoDepsCopy/source-registry-0/rdev-0.5.3/src/macos/keyboard.rs \
      --replace-fail \
        '        let mut keyboard = TISCopyCurrentKeyboardInputSource();' \
        '        extern "C" {
            fn pthread_main_np() -> i32;
        }
        if pthread_main_np() == 0 {
            return None;
        }
        let mut keyboard = TISCopyCurrentKeyboardInputSource();'

    # Keep the Dock icon out: this is a tray app that runs from login to
    # shutdown, so a permanent Dock tile buys nothing. LSUIElement alone does
    # not work - tao calls setActivationPolicy(Regular) from
    # applicationDidFinishLaunching and overrides the plist. Dioxus builds the
    # event loop itself (app.rs: EventLoopBuilder::with_user_event().build())
    # and never exposes the policy, and Config::with_event_loop cannot be used
    # from outside the crate because UserWindowEvent is not re-exported, so the
    # only seam is tao's own default.
    substituteInPlace $cargoDepsCopy/source-registry-0/tao-0.34.5/src/platform_impl/macos/app_delegate.rs \
      --replace-fail \
        'activation_policy: ActivationPolicy::Regular,' \
        'activation_policy: ActivationPolicy::Accessory,'
  '';

  # No tests in the tree, and buildRustPackage's default check would only rebuild
  # the whole crate as a test binary.
  doCheck = false;

  # Hand-assembled, mirroring scripts/build-macos-app.sh. `dx bundle` is not used
  # for the same reason upstream avoids it: DioxusLabs/dioxus#5723 makes its
  # resource copier fail on every directory entry, leaving an empty Resources.
  #
  # soundpacks/ is what src/state/paths.rs resolves through ../Resources, and
  # assets/ must be there too because dioxus-asset-resolver hardcodes
  # Contents/Resources as the asset root on macOS.
  installPhase = ''
        runHook preInstall

        app=$out/Applications/${appName}.app
        mkdir -p $app/Contents/MacOS $app/Contents/Resources $out/bin

        install -m755 target/${stdenv.hostPlatform.rust.cargoShortTarget}/release/mechvibes-dx \
          $app/Contents/MacOS/mechvibes-dx
        cp -R soundpacks assets README-macos.txt $app/Contents/Resources/

        for size in 16 32 128 256 512; do
          magick assets/icon.png -resize "$size"x"$size" icon_$size.png
        done
        png2icns $app/Contents/Resources/${appName}.icns icon_*.png

        # Not indented: a plist must start with <?xml at byte 0.
        cat > $app/Contents/Info.plist << PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleExecutable</key>
        <string>mechvibes-dx</string>
        <key>CFBundleIconFile</key>
        <string>${appName}</string>
        <key>CFBundleIdentifier</key>
        <string>com.hainguyents13.mechvibesdx</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>${appName}</string>
        <key>CFBundleDisplayName</key>
        <string>${appName}</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleShortVersionString</key>
        <string>${version}</string>
        <key>CFBundleVersion</key>
        <string>${version}</string>
        <key>LSMinimumSystemVersion</key>
        <string>11.0</string>
        <!-- Suppresses the Dock icon before the event loop starts; the tao
             patch above is what keeps it hidden afterwards. -->
        <key>LSUIElement</key>
        <true/>
        <key>NSHighResolutionCapable</key>
        <true/>
        <key>NSSupportsAutomaticGraphicsSwitching</key>
        <true/>
    </dict>
    </plist>
    PLIST

        ln -s $app/Contents/MacOS/mechvibes-dx $out/bin/mechvibes-dx

        runHook postInstall
  '';

  # A silent app is the failure this bundle shipped once upstream, so assert the
  # copy landed rather than trusting it.
  postInstall = ''
    packs=$(find $out/Applications/${appName}.app/Contents/Resources/soundpacks \
      \( -name '*.ogg' -o -name '*.mp3' -o -name '*.wav' \) | wc -l)
    expected=$(find soundpacks \( -name '*.ogg' -o -name '*.mp3' -o -name '*.wav' \) | wc -l)
    if [ "$packs" -ne "$expected" ]; then
      echo "bundled $packs soundpack audio files, source tree has $expected"
      exit 1
    fi
  '';

  meta = {
    description = "Mechanical keyboard sound simulator (Mechvibes successor)";
    homepage = "https://github.com/hainguyents13/mechvibes-dx";
    license = lib.licenses.mit;
    mainProgram = "mechvibes-dx";
    platforms = lib.platforms.darwin;
  };
}
