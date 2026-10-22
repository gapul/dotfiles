{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
  appimageTools,
  makeDesktopItem,
}:
let
  pname = "syncclipboard";
  version = "3.3.3";
  baseUrl = "https://github.com/Jeric-X/SyncClipboard/releases/download/v${version}";
  meta = {
    description = "Cross-platform clipboard synchronization";
    homepage = "https://github.com/Jeric-X/SyncClipboard";
    license = lib.licenses.mit;
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
in
if stdenvNoCC.hostPlatform.isDarwin then
  stdenvNoCC.mkDerivation {
    inherit pname version meta;
    src = fetchurl {
      url = "${baseUrl}/SyncClipboard_macos_arm64.dmg";
      hash = "sha256-viDdA7rs1eA+769nozB8j19VQiQ+eKmFyuiBXoC9CzE=";
    };
    nativeBuildInputs = [ undmg ];
    sourceRoot = ".";
    dontPatchShebangs = true;
    dontStrip = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      find . -name '._*' -delete
      mkdir -p "$out/Applications"
      cp -R SyncClipboard.app "$out/Applications/"
      runHook postInstall
    '';
  }
else
  appimageTools.wrapType2 {
    inherit pname version;
    src = fetchurl {
      url = "${baseUrl}/SyncClipboard_linux_x64.AppImage";
      hash = "sha256-SeCvB7MAGZ3MkttZNu0cAcHPdWlk/fIIS37y0SaCZGc=";
    };
    extraPkgs = pkgs: [
      pkgs.icu
      pkgs.wl-clipboard
      pkgs.xclip
    ];
    extraInstallCommands = ''
      mkdir -p "$out/share/applications"
      cp ${
        makeDesktopItem {
          name = pname;
          desktopName = "SyncClipboard";
          exec = pname;
          categories = [ "Utility" ];
        }
      }/share/applications/* "$out/share/applications/"
    '';
    meta = meta // {
      mainProgram = pname;
    };
  }
