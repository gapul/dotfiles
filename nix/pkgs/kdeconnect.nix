# KDE Connect (macOS). Replaces the cask from my own tap `gapul/kdeconnect`.
#
# Two reasons for dropping the tap.
#
# 1. **It wasn't verified.** The cask used `sha256 :no_check` and installed the executable binary
#    straight from KDE's CDN. Here it gets a real hash.
# 2. **It was already broken.** Build 6325 of master that the cask pinned is gone from the CDN
#    (the CI directory prunes old ones). It only worked locally because it was already installed;
#    a clean machine gets a 404. Pinning a build number just doesn't hold up as a design.
#
# The tracked branch also changed from master to the release branch. master is nightly, so it would
# take every day's changes directly. release-26.08 moves within the stable series.
#
# To bump the version, look at the directory below and swap the build number and hash:
#   https://cdn.kde.org/ci-builds/network/kdeconnect-kde/release-26.08/macos-arm64/
# Old numbers disappear, so if it drops out of the store without being bumped it can't be re-fetched.
# It survives while it is in attic / cachix, but don't lean on that.
#
# The signature is the genuine KDE e.V. Developer ID (team 5433B4KXM8). So shipping it without
# touching the contents keeps TCC grants alive (nix-darwin's /Applications/Nix Apps is a copied tree
# of the real files, so the path is stable too). Building from source gives an ad-hoc signature and
# the local network permission gets dropped every time, so that is not done.
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "kdeconnect";
  # Upstream's macOS builds carry no version number, only the release series and a CI sequence number.
  # The file name is literally `release_<version>`, so fixing this makes the URL follow.
  # When crossing series (26.08 → 26.12 etc.), also fix `release-26.08` in the directory part.
  version = "26.08-6635";

  src = fetchurl {
    url = "https://cdn.kde.org/ci-builds/network/kdeconnect-kde/release-26.08/macos-arm64/kdeconnect-kde-release_${finalAttrs.version}-macos-clang-arm64.dmg";
    hash = "sha256-Qs3qPHLKoL7O2nvW6ve/3SGZC56/zTr2k+tZLZU7ZvE=";
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";

  # Signed bundle, so the contents are not touched at all.
  dontPatchShebangs = true;
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    # dmg の展開が AppleDouble のサイドカーを書き出すことがあり、署名が封印していない
    # ファイルが増えると `codesign -v` が落ちる (pkgs/terminal-browser.nix と同じ罠)。
    find . -name '._*' -delete
    find . -name '.DS_Store' -delete
    mkdir -p "$out/Applications"
    cp -R "KDE Connect.app" "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "Enabling communication between all your devices";
    homepage = "https://kdeconnect.kde.org/";
    license = lib.licenses.gpl2Plus;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
