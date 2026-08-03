{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.12.0";
  sources = {
    aarch64-darwin = {
      arch = "arm64";
      hash = "sha256-YU4uyBKo9lmVAmjkCoQxTaDGPNV3MBzqgMbDIWD86q8=";
    };
    x86_64-darwin = {
      arch = "x86_64";
      hash = "sha256-fYdGpcM/yIHbZBPFo2hv6Mg6bgvV2/d8jVSnEBjpqiM=";
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
