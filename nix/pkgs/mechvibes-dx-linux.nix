{
  appimageTools,
  fetchurl,
  lib,
}:
let
  pname = "mechvibes-dx";
  version = "0.8.1";
  src = fetchurl {
    url = "https://github.com/hainguyents13/mechvibes-dx/releases/download/v${version}/mechvibes-dx-${version}-x86_64.AppImage";
    sha256 = "a5d1bcfefccf47ae5a17615120aaa259b7137f437ffaf9bd807502eadf51b284";
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
