{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.40.0";
  sources = {
    aarch64-darwin = {
      arch = "arm64";
      hash = "sha256-XlgHaF8/w27OiruPxiqaYzr5GUfhOr+dX9Tdv5Oc5qo=";
    };
    x86_64-darwin = {
      arch = "x86_64";
      hash = "sha256-1gZ8VXBcH3XGXOAZrJ48HX2ItZW0Al2YNdyc2Md42t4=";
    };
  };
  source = sources.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "slk";
  inherit version;

  src = fetchurl {
    url = "https://github.com/gammons/slk/releases/download/v${version}/slk_${version}_darwin_${source.arch}.tar.gz";
    inherit (source) hash;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 slk $out/bin/slk
    runHook postInstall
  '';

  meta = {
    description = "Fast, keyboard-driven Slack TUI client";
    homepage = "https://getslk.sh/";
    license = lib.licenses.mit;
    mainProgram = "slk";
    platforms = builtins.attrNames sources;
  };
}
