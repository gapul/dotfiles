# Vendored from the private fork gapul/azoo-key-skkserv (nix/package.nix), which is the copy to
# change first: the fork stays private, and dotfiles is public, so it is not a flake input here.
#
# The Linux build, as a Nix package that runs on NixOS.
#
# This repackages upstream's Linux release rather than compiling it. The release is built in the
# swift:latest image with --static-swift-stdlib, so beyond the bundled llama.cpp it needs only
# libstdc++/libgcc_s/libgomp and glibc, which autoPatchelfHook points at the store. Compiling
# from source does not work with nixpkgs' Swift 6.2.4 yet: Package.swift turns on C++ interop,
# and Swift's bundled clang 17 cannot parse the gcc 16 libstdc++ headers nixpkgs now defaults to
# (it fails as early as swift-collections). Rebuilding the toolchain against an older gcc would
# fix that at the cost of hours per nixpkgs bump; the fork's flake.nix keeps a devShell for the source build.
#
# The one change from upstream's release is llama.cpp. The release bundles ggml-org's b4846, which
# does not know zenz-v1's "gpt2-small-japanese-char" pre-tokenizer: the model fails to load
# ("unknown pre-tokenizer type") and the server quietly runs on the dictionary alone, without
# Zenzai. azooKey's own llama.cpp fork at the same tag, which the macOS build links, does know it,
# and its Ubuntu release has the same set of .so files, so those replace the bundled ones.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
}:
let
  version = "0.4.0";
  triple =
    {
      x86_64-linux = "x86_64-unknown-linux-gnu";
      aarch64-linux = "aarch64-unknown-linux-gnu";
    }
    .${stdenv.hostPlatform.system};
  hashes = {
    x86_64-linux = "sha256-fHNqj/zs1RcJ8Wgg0hNHg1sBkYdFqbgt5m+xRUR63Q8=";
    aarch64-linux = "sha256-BtK1Av0WHbo8wkKbi1KZPfZCZTMWEiJB7tU88sIKD7E=";
  };

  llamaTag = "b4846";
  llama =
    {
      x86_64-linux = {
        arch = "x64";
        hash = "sha256-3lblgDU0vd2Y0vPlQ6R3U/vuLtSbGfMdCuCz7CkmZ5M=";
      };
      aarch64-linux = {
        arch = "arm64";
        hash = "sha256-JK3znVP81yR26glMBTcqogQ2pv5Y/EyYZHFKpdUfa6A=";
      };
    }
    .${stdenv.hostPlatform.system};
  llamaSrc = fetchurl {
    url = "https://github.com/azooKey/llama.cpp/releases/download/${llamaTag}/llama-${llamaTag}-bin-ubuntu-${llama.arch}.zip";
    inherit (llama) hash;
  };
in
stdenv.mkDerivation {
  pname = "azoo-key-skkserv";
  inherit version;

  src = fetchurl {
    url = "https://github.com/gitusp/azoo-key-skkserv/releases/download/v${version}/${triple}-${version}.zip";
    hash = hashes.${stdenv.hostPlatform.system};
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
    cp -r azoo-key-skkserv *.resources $dir/
    mkdir $dir/lib
    unzip -q -j ${llamaSrc} 'build/bin/*.so' -d $dir/lib
    ln -s $dir/azoo-key-skkserv $out/bin/azoo-key-skkserv
    runHook postInstall
  '';

  preFixup = ''
    addAutoPatchelfSearchPath $out/libexec/azoo-key-skkserv/lib
  '';

  meta = {
    description = "skkserv backed by AzooKeyKanaKanjiConverter and the Zenzai neural converter";
    homepage = "https://github.com/gitusp/azoo-key-skkserv";
    # The program is MIT; the bundled zenz-v1 model is CC-BY-SA 4.0.
    license = with lib.licenses; [
      mit
      cc-by-sa-40
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "azoo-key-skkserv";
  };
}
