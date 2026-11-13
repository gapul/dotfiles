{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-3my0bBrBhx1SSWXtLtXxTh6xO0/CUhCiCaVcCxFUAU8=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-LOnzy9xTfkRo8Xg4J0lQjsp8YRz0swTMIzlcYzIafZY=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-lTTTqYySF49Kv8jn1Qpi35HaGQ24OLxlduiYJVImmjc=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-vWgAVctKjZ0kTHDXnu+lgo9maAdQl1WVR+HKSuzgeys=";
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
