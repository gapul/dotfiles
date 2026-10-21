{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.14";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-Nn6hJMYekdwiQJaZy0DS5l0jlS8yIOkRzOofbYof838=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-V4xZI638ueHHicF+o0SgpxypS2loFVCnkyYLqJDuIvw=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-SFQE3KG2oh29w4JJrO1pv6ncLLJtyZW8Hyn+m4YMUdU=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-2aLBcWznI7lwiY9/QK3AnM7uBOhM4vHxY48HrD6YmKo=";
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
