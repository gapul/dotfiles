{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.16";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-hI8ZyR3WkmleAa4wjguyMGDFR7EAjlhmOkc9OM1Wh3I=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-k8SQlZge6xP9oLouRzuufZLTNOzZGM7l+J0chHAsiZQ=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-ICNoX1RPixBaxIIMyY0eV+b8d70p9x/jqyCVzUczxrI=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-pfTS7Y99/EpcsoHclt/L9V0+robg5CTzfuyYUH4mR08=";
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
