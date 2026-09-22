{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.10";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-rnDdszAcyFmb1MfeGsC2VFLoOmL85gMUWFIQHbufZu8=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-hLLQ2t6SvHp2DeArfRmJGZUxF+4gV5D1npuDknh4zUE=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-66gGNoq3B3LP+KmmLIOfoQnxnZAmWWE/M+XqkDwb9i8=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-EKUUZADAktoGeDJ+Fn7cf327NU8bP9dqVTWZDe4SXac=";
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
