{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.0.0-beta.12";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-fyF0b+eyzxAQp/KTdjrZWQcVFmFH3MBAGntS3g2V8Qc=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-kC023J746+f2kVZzAT3LykNaNH+u4MdXned8OdbofHg=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-kVNixayTJaPVyMb51t3SOXteNfEERGp3Kdf9+57eFrQ=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-EsrfWQDEhcvRfKIH2HmTv5p4FMPsgmumlr19gPYrEUY=";
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
