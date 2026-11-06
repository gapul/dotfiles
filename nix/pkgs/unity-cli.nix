{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.17";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-sUzlHi+HLzCuHontnvD/0HqgYWD5GKrewJRxsvgoRus=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-XyJA92gocUSHBuES9+3iNverAuziZ5scuKehSMcppg8=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-T9iAoOdAbemGdH5fSEcxqYOOCXqeDnD09sTaqUY+L8E=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-L1JG7lvqUDLaKRf18BJdPP6APIXcNPeL11pCfbE6Czw=";
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
