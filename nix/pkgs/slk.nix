{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.20.0";
  sources = {
    aarch64-darwin = {
      arch = "arm64";
      hash = "sha256-1IkWqeUPX2r9qyEQRfbKu4HFfNEBDjq3EdugHS7+C0I=";
    };
    x86_64-darwin = {
      arch = "x86_64";
      hash = "sha256-HAAkBW2Fu7rCHKB3LeiRZ6b7/bqyu+8J2pzVOn4ZKwY=";
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
