{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.1";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-0Dh55L1+2TR0O/aBnCMGLop9+rXUpiw3OvOjldtMtIc=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-BU9ban0W72vXkHCVa+lE4erkA279nRxZOBTFOKEIFCY=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-vTo5m6HlqogwNmjF2IrY4LGBT71XhKSQ4fUwSIJpLr4=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-o451Yx7d5blt+OCjfi64yNHrGmujD9QcNPK6rHk7WzE=";
    };
  };
  source = sources.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "unity-cli";
  inherit version;

  src = fetchurl {
    url = "https://public-cdn.cloud.unity3d.com/hub/prod/cli/${version}/unity-${source.platform}";
    inherit (source) hash;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/unity
    runHook postInstall
  '';

  meta = {
    description = "Official standalone CLI for managing Unity Editors, modules, and projects";
    homepage = "https://docs.unity.com/en-us/unity-cli/";
    license = lib.licenses.unfree;
    mainProgram = "unity";
    platforms = builtins.attrNames sources;
  };
}
