# SlimeVR Server - the receiver half of the SlimeVR full-body tracking stack.
#
# Used here with mocopi rather than SlimeVR's own trackers: mocopi's app has
# had a SlimeVR mode since ver 2.0.0, so the phone sends straight to this
# server. That path avoids mocopi's own drift handling, which is the part users
# complain about, and it makes the reset a chest double-tap instead of a
# recalibration pose. The server speaks VMC out, so nijiexpose and other VTuber
# runtimes can read the result.
#
# Not taken from nixpkgs: `slimevr-server` there is `broken = isDarwin`, and
# even unbroken it builds only the headless jar (its libhidapi shim links
# `libhidapi-hidraw.so`, which is Linux-only). The GUI is where tracker
# assignment, body proportions and the mounting reset live, so the official
# universal build is repackaged instead.
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
let
  version = "20.1.0";
  app = "SlimeVR.app";
in
stdenvNoCC.mkDerivation {
  pname = "slimevr-server";
  inherit version;

  src = fetchurl {
    url = "https://github.com/SlimeVR/SlimeVR-Server/releases/download/v${version}/SlimeVR-mac.dmg";
    hash = "sha256-M3JlnTYq8EdrQQ1y0tWfI2VRcOLGtcVMudJnDXhBiL4=";
  };

  # undmg, not 7zz: the image is HFS+ (only VRoid's is APFS, which is why that
  # one needs 7zz). It matters here beyond convenience — 7zz materialises the
  # HFS+ attribute forks as literal `app.asar:com.apple.cs.CodeDirectory` files
  # and the seal no longer verifies, while undmg leaves `codesign -v --strict`
  # passing.
  nativeBuildInputs = [ undmg ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R "${app}" "$out/Applications/${app}"
    runHook postInstall
  '';

  # Upstream signs ad hoc (TeamIdentifier is not set), so `spctl` rejects the
  # bundle — it is neither Developer ID signed nor notarised. That does not stop
  # it here: store paths never carry com.apple.quarantine, so Gatekeeper is not
  # consulted at launch. Same situation as pkgs/vroid-studio.nix.
  #
  # The consequence to know about is macOS 15's Local Network permission, which
  # the server needs to hear trackers (and mocopi) on the LAN. TCC identifies an
  # ad-hoc signed app by its code directory hash, so the grant has to be given
  # again after every version bump.
  postInstall = ''
    exe="$out/Applications/${app}/Contents/MacOS/SlimeVR"
    if [ ! -x "$exe" ]; then
      echo "expected executable missing: $exe"
      exit 1
    fi
  '';

  meta = {
    description = "Server for the SlimeVR full-body tracking ecosystem";
    homepage = "https://docs.slimevr.dev/";
    license = with lib.licenses; [
      mit
      asl20
    ];
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
}
