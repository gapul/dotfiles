# Vendored from the fork gapul/azoo-key-skkserv (nix/package.nix), which is the copy to change
# first. It is copied rather than taken as a flake input so the fork brings no nixpkgs of its own.
#
# The Linux build, as a Nix package that runs on NixOS.
#
# This repackages the fork's Linux release rather than compiling it. The release is built in the
# swift:6.2-jammy image with --static-swift-stdlib, so beyond the bundled llama.cpp it needs only
# libstdc++/libgcc_s/libgomp and glibc, which autoPatchelfHook points at the store. Compiling
# from source does not work with nixpkgs' Swift 6.2.4 yet: Package.swift turns on C++ interop,
# and Swift's bundled clang 17 cannot parse the gcc 16 libstdc++ headers nixpkgs now defaults to
# (it fails as early as swift-collections). Rebuilding the toolchain against an older gcc would
# fix that at the cost of hours per nixpkgs bump; the fork's flake.nix keeps a devShell for the
# source build.
#
# The release's lib/ is azooKey's llama.cpp fork (b4846), not ggml-org's b4846 that upstream's
# releases bundle: the latter does not know zenz's "gpt2-small-japanese-char" pre-tokenizer, so
# the model fails to load ("unknown pre-tokenizer type") and the server quietly runs on the
# dictionary alone, without Zenzai. Only x86_64-linux is released.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
}:
let
  version = "0.5.0";
  triple = "x86_64-unknown-linux-gnu";
in
stdenv.mkDerivation {
  pname = "azoo-key-skkserv";
  inherit version;

  src = fetchurl {
    url = "https://github.com/gapul/azoo-key-skkserv/releases/download/v${version}/${triple}-${version}.zip";
    hash = "sha256-bvpLN1pnZzzLbQqSb4sYo5Bn7bNoez6QNhMWAIKrMvI=";
  };

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
  ];
  # libstdc++, libgcc_s and libgomp (the last for llama.cpp's CPU backend).
  buildInputs = [ stdenv.cc.cc.lib ];

  sourceRoot = "${triple}/release";

  dontConfigure = true;
  dontBuild = true;

  # Bundle.module looks for the *.resources directories (the zenz model and the dictionaries) next
  # to the executable, resolved through /proc/self/exe, so they stay together in libexec and bin
  # holds only a symlink. lib/ is llama.cpp, found through the binary's $ORIGIN/lib RUNPATH.
  installPhase = ''
    runHook preInstall
    dir=$out/libexec/azoo-key-skkserv
    mkdir -p $dir $out/bin
    cp -r azoo-key-skkserv *.resources lib $dir/
    ln -s $dir/azoo-key-skkserv $out/bin/azoo-key-skkserv
    runHook postInstall
  '';

  preFixup = ''
    addAutoPatchelfSearchPath $out/libexec/azoo-key-skkserv/lib
  '';

  meta = {
    description = "skkserv backed by AzooKeyKanaKanjiConverter and the Zenzai neural converter";
    homepage = "https://github.com/gapul/azoo-key-skkserv";
    # The program is MIT; the bundled zenz-v3.2-small model is CC-BY-SA 4.0.
    license = with lib.licenses; [
      mit
      cc-by-sa-40
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "azoo-key-skkserv";
  };
}
