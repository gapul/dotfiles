{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.6";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-LpsYpnQrlVroHDYgo7IILmZHBCY7IGq5DGLNngJcauU=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-/RuahJ+F4/Ls77XIH74tScdA5ofnSqh2mFXGYjGwXwk=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-yEnwgAgqmRK+aJ5grICZ0fCCPCqMl+9xDWoi5nlSzGw=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-i1I/0C5R/STVgaiMT3SnVglOMIyOwNm5qMlfQj/Zw9w=";
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
