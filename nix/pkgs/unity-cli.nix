{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.11";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-9rVLnZpGpVaPUSPUet3mZgXHM0ulfGAWdy0V08+S3fc=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-nt0aHF0JMq9itNcIspObKgjYYCzjmZZFVmpJ5DGiApA=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-HlUiLxxM/NzQIw7WITcCUpEbreua2w825/Bx3aPQ2Tg=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-aEvyKYgZY8cxiVpOdEzfVBvoAJEtaPoc6kBxW2Ox05Y=";
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
