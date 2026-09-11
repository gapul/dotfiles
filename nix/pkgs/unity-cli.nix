{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.9";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-RZ1oMKQR34bp2wV5uAOTLwxrwu/2p6tIM4XxZ2/ash8=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-XpiYkUTdJKC3TNsqXKCGdOHsf2hH/qA+6s1+621M0ZY=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-Z3WydFM7lKVqzJScOoAjPcFdXFISfZuj9pGC+TH84Ns=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-jA1uJDVEnIvn8OayzmMwv8XxepiuxLZZyFmUBFXdD+U=";
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
