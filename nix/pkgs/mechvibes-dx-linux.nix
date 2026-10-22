{
  appimageTools,
  fetchurl,
  lib,
}:
let
  pname = "mechvibes-dx";
  version = "0.8.4";
  src = fetchurl {
    url = "https://github.com/hainguyents13/mechvibes-dx/releases/download/v${version}/mechvibes-dx-${version}-x86_64.AppImage";
    hash = "sha256-G5w7fP8v4JrM51Fr8ZYnV2e8CvnxNo6SzfPByupZZbU=";
  };
in
appimageTools.wrapType2 {
  inherit pname version src;
  # The upstream binary links libxdo.so.3; current nixpkgs ships ABI 4.
  extraPkgs = pkgs: [
    pkgs.libsoup_3
    pkgs.openssl
    pkgs.webkitgtk_4_1
    pkgs.libayatana-appindicator
    (pkgs.xdotool.overrideAttrs (_: {
      version = "3.20211022.1";
      src = pkgs.fetchFromGitHub {
        owner = "jordansissel";
        repo = "xdotool";
        rev = "v3.20211022.1";
        hash = "sha256-XFiaiHHtUSNFw+xhUR29+2RUHOa+Eyj1HHfjCUjwd9k=";
      };
    }))
  ];
  extraInstallCommands = ''
    mkdir -p $out/share/applications
    cat > $out/share/applications/mechvibes-dx.desktop <<DESKTOP
    [Desktop Entry]
    Type=Application
    Name=MechvibesDX
    Exec=$out/bin/mechvibes-dx
    Terminal=false
    Categories=Utility;
    DESKTOP
  '';
  meta = {
    description = "Mechanical keyboard sound simulator";
    homepage = "https://github.com/hainguyents13/mechvibes-dx";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "mechvibes-dx";
  };
}
