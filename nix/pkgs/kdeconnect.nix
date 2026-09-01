# KDE Connect (macOS). 自作 tap `gapul/kdeconnect` の cask を置き換える。
#
# tap をやめた理由は 2 つ。
#
# 1. **検証していなかった。** cask は `sha256 :no_check` で、KDE の CDN から降ってきた実行
#    バイナリをそのまま入れていた。ここでは実ハッシュが付く。
# 2. **すでに壊れていた。** cask が固定していた master の build 6325 は CDN から消えている
#    (CI ディレクトリは古いものを刈る)。手元で動いていたのはインストール済みだったからで、
#    まっさらな機械では 404 になる。番号を固定する設計そのものが保たない。
#
# 追随先も master から release ブランチに変えた。master は nightly なので、日々の変更を
# そのまま浴びることになる。release-26.08 なら安定版系列の中で動く。
#
# 版を上げるときは、下のディレクトリを見て build 番号とハッシュを差し替える:
#   https://cdn.kde.org/ci-builds/network/kdeconnect-kde/release-26.08/macos-arm64/
# 古い番号は消えるので、上げないまま store から消えると取り直せない。attic / cachix に
# 載っている間は残るが、それに寄りかからないこと。
#
# 署名は KDE e.V. の Developer ID (team 5433B4KXM8) が付いた正規のもの。だから中身を
# 触らずに運べば TCC の付与が生き残る (nix-darwin の /Applications/Nix Apps は実体の
# コピーツリーなので、パスも安定している)。ビルドから作ると ad-hoc 署名になって
# ローカルネットワークの許可が毎回外れるので、そこはやらない。
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "kdeconnect";
  # 上流の macOS ビルドにバージョン番号は付かず、リリース系列と CI の通し番号しかない。
  # ファイル名がそのまま `release_<version>` なので、ここを直せば URL も追う。
  # 系列を跨ぐとき (26.08 → 26.12 など) はディレクトリ側の `release-26.08` も直すこと。
  version = "26.08-6543";

  src = fetchurl {
    url = "https://cdn.kde.org/ci-builds/network/kdeconnect-kde/release-26.08/macos-arm64/kdeconnect-kde-release_${finalAttrs.version}-macos-clang-arm64.dmg";
    hash = "sha256-kDxboch/BgzbI7ildyOlgTC2F7P3+r7gDFGg1mZSJmo=";
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";

  # 署名済みバンドルなので中身は一切いじらない。
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
