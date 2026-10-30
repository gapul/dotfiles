{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.15";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-Hp4J1CkGIzjcalYpAHWCnnMXY6mzo7bJY/O+DBKySPQ=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-hl7Z3k3ROkvLMxo0N3De5myLq++24a2Y8SVsUpatFnQ=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-kZF4vum6gn9PUrD8XnE/yuZjq/I1EttzSI282yNCKV8=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-zz3e8mC7pTYzI0i9VXD7gNkKgJJ4Sok7MJcfjr8qSJ4=";
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
