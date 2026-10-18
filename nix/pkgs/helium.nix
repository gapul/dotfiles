{
  appimageTools,
  fetchurl,
  lib,
  makeDesktopItem,
}:
let
  pname = "helium";
  version = "0.19.2.1";
  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
    sha256 = "a04550a3c7c70bdad3acd3a4430eda8d2afc0bf7173a9c58a403feab9517087f";
  };
  desktop = makeDesktopItem {
    name = "helium";
    desktopName = "Helium";
    exec = "helium %U";
    icon = "helium";
    categories = [
      "Network"
      "WebBrowser"
    ];
    mimeTypes = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  extraInstallCommands = ''
    mkdir -p $out/share/applications $out/share/icons/hicolor/256x256/apps
    cp ${desktop}/share/applications/helium.desktop $out/share/applications/
    if [ -f ${contents}/helium.png ]; then
      cp ${contents}/helium.png $out/share/icons/hicolor/256x256/apps/helium.png
    fi
  '';
  meta = {
    description = "Private and independent Chromium-based web browser";
    homepage = "https://helium.surf";
    license = lib.licenses.gpl3;
    platforms = [ "x86_64-linux" ];
    mainProgram = "helium";
  };
}
