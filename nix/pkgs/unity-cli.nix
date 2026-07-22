{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.2";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-5H9tvWMelhNF1+/2TwxfBXFYenpVB3uv0TZ048HyEDA=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-W7+0IUxgjGLRZlcOMXkKMKsHLlwCjKxP16dQRdQ2+Oo=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-J+qs7N4rPm3gjkDt3JtOkFjTArIeNq0e1i0hUHHZMAM=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-OdP3tn5FqWQgeiDNYvWbn4QrusyKXaZgV3G3gUutNZ8=";
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
