# AskApprove: the Touch ID approval helper the ask broker (configs/ask/ask_broker.py) opens.
#
# Built with Xcode's swiftc and signed with the Developer ID by helper/build.sh in gapul/ask —
# nixpkgs' swift cannot link LocalAuthentication, and the signature is what the broker's `open`
# launch relies on — so the signed artifact is carried, not rebuilt. gapul/ask is private, which
# fetchurl cannot reach, hence requireFile: take the zip from the release once per version.
#
#   gh release download approve-v1 -R gapul/ask -p AskApprove-1.zip
#   nix-store --add-fixed sha256 AskApprove-1.zip
{
  stdenvNoCC,
  requireFile,
  unzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "askapprove";
  version = "1";

  src = requireFile {
    name = "AskApprove-${finalAttrs.version}.zip";
    hash = "sha256-440xhsciCgBEj8J8e9fZ6CwfsFBXvgeMvEZ2Tg8s+Mc=";
    url = "https://github.com/gapul/ask/releases/tag/approve-v${finalAttrs.version}";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";

  dontPatchShebangs = true;
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    find . -name '._*' -delete
    mkdir -p $out/Applications
    cp -R AskApprove.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "Touch ID approval helper for the ask broker";
    homepage = "https://github.com/gapul/ask";
    platforms = [ "aarch64-darwin" ];
  };
})
