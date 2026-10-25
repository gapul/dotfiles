{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.28.1";
  sources = {
    aarch64-darwin = {
      arch = "arm64";
      hash = "sha256-3Ob+mmOHN3YMmo+UJ2u9dy2Ki845PbRmUb73SiEpCPU=";
    };
    x86_64-darwin = {
      arch = "x86_64";
      hash = "sha256-jM3OU3GSIu/EX7/CfeipTDmNA13NZ/AGGV5Z57OyvQg=";
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
