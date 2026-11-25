{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.1.0";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-8pIlX5lDR2TWG4z2G3LzvmDgODk0tMNfgtnaqnKqagU=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-lphQxtI3dSPGbD9RnukNWsnNOd4/Thag+RSv9dg/iQM=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-+YGVTofAjO8y31CErK6gzIjHFNsuI4q5pC8LRuqHKlE=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-eAx4Xtp0ee7S7bjRUcSQvzO1QOuwiXKWXo1IJju2irA=";
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
