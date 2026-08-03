{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.3";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-rfttvUvCAVBSpj0gl+xTW1QI9YXi4183VLmV4VQe70g=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-0NOzVtEH8zPoZvcrlv9ED4EJdnFd+T3XnqKmt3fDtQ8=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-Idor+Y0W261V3Tuxh6AQCKz+CDlgdeSRiA2X2Bip7xE=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-m4mqpaZ26OW9ajhEqTmN77ljvTSVGGRFpGSkcFflTqM=";
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
