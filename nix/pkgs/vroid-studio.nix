# VRoid Studio - pixiv's 3D character (VRM) modelling app.
#
# Not in nixpkgs and there is no Homebrew cask, so the official macOS build is
# repackaged here. This is the standalone download from vroid.com, deliberately
# not the Steam build: Steam ships the same binary but drags the Steam client
# along, which is not worth declaring for a machine that only needs to open the
# app now and then. The bundle is a universal binary, so it runs natively on
# Apple Silicon.
{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:
let
  version = "2.14.0";

  # The stable download URL carries a per-release token in its path. It is not
  # derivable from the version: dropping it 403s, and so does reusing this token
  # with an older version (checked against 2.13.0 / 2.12.0). Only the beta
  # channel uses a plain /dist/<file> path. So this has to be re-read from
  # <https://vroid.com/en/studio> on every bump - that page is server-rendered
  # and the href appears verbatim in the HTML, so grepping it is enough.
  distToken = "VHpx0Opa4q";

  app = "VRoidStudio.app";
in
stdenvNoCC.mkDerivation {
  pname = "vroid-studio";
  inherit version;

  src = fetchurl {
    url = "https://download.vroid.com/dist/${distToken}/VRoidStudio-v${version}-mac.dmg";
    hash = "sha256-/1VXILqocXML0PCAbSlrWqQXfnt6W4yXpcfnQkzX31c=";
  };

  # undmg cannot read this image ("only HFS file systems are supported") because
  # the dmg is APFS. 7zz handles APFS, and unlike hdiutil it works inside the
  # build sandbox.
  nativeBuildInputs = [ _7zz ];

  unpackPhase = ''
    runHook preUnpack
    7zz x -snld $src
    runHook postUnpack
  '';

  sourceRoot = ".";

  # pixiv's signature (Team Q76D8M83GL) does NOT survive this. Some nested
  # resources - Unity's StreamingAssets/aa/catalog.bundle among them - keep their
  # signature in extended attributes (com.apple.cs.CodeDirectory and friends),
  # and 7zz cannot restore those; -sns does not help, it only covers NTFS
  # streams. So `codesign -v` on the result reports "a sealed resource is missing
  # or invalid".
  #
  # Left as is rather than ad-hoc re-signing 1.3GB on every build, because it
  # does not stop the app: store paths never carry com.apple.quarantine, so
  # Gatekeeper is not consulted at launch, and this was verified by actually
  # running the built bundle. If a future macOS starts enforcing this, or if the
  # app ever needs a TCC grant (those key on the signature), re-sign here with
  # sigtool instead of reaching for hdiutil - hdiutil cannot attach an image
  # inside the build sandbox.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R "${app}" "$out/Applications/${app}"
    runHook postInstall
  '';

  # 7zz decides the layout, so assert the bundle actually came out whole instead
  # of trusting it - a renamed or half-extracted .app would otherwise only show
  # up as an app that refuses to launch.
  postInstall = ''
    exe="$out/Applications/${app}/Contents/MacOS/VRoid Studio"
    if [ ! -x "$exe" ]; then
      echo "expected executable missing: $exe"
      exit 1
    fi
  '';

  meta = {
    description = "3D character modelling app that exports VRM (pixiv)";
    homepage = "https://vroid.com/studio";
    # Free of charge but proprietary. See License.txt inside the dmg.
    license = lib.licenses.unfree;
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
}
