{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.26.2";
  sources = {
    aarch64-darwin = {
      arch = "arm64";
      hash = "sha256-barDjZg2UHWcqTWJmm+1pqaFqOHyBkwChjle8dWARwM=";
    };
    x86_64-darwin = {
      arch = "x86_64";
      hash = "sha256-tDBEVvc8CN2tZZfPeA5qxIAytxQ95oWN5v/K9gl+wAQ=";
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
