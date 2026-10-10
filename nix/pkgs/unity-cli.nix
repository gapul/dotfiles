{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.13";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-m/t07wpvxOmAHH6Mgp1Jibi2BlPwNqYLn+N+D2oQUiA=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-Ft9srTZo4mzWupFHRKfCUKBCPmk26wFth+ipM2VuYoc=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-LNnm7xCgg/pFT4+l7+q/Kn8237pePTjZ4O4NMM6FiP8=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-qE2s4fXoW2Kf/4Qd38Xsjpf9KheCQvypHIC8VoAUL7M=";
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
