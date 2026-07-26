# ghostty-launcher の検索バックエンド (Rust)。
# 従来はリポジトリ内で `cargo build --release` し core/launcher-search シンボリックリンク
# 経由で参照していたが、生成物 target/ が `just gc-deep` の「30日触っていない rust target」
# 掃除に巻き込まれて消え、ランチャーが起動不能になる事故があった。
# nix store にビルドして LAUNCHER_SEARCH_BIN で指すことで、GC ルートに保護され
# `nh home switch` のたびに再生成される (target/ 不要)。
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage {
  pname = "launcher-search";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "gapul";
    repo = "ghostty-launcher";
    rev = "0345bb76d6b3a095e0827a32ff19ab93b99743ad";
    hash = "sha256-myoYR0K+2ty+FQed/u9o+lNt6/DKFtHu4BAR1dZ21Ww=";
  };

  # crate はリポジトリ直下ではなく launcher-search/ サブディレクトリにある。
  cargoRoot = "launcher-search";
  buildAndTestSubdir = "launcher-search";

  cargoHash = "sha256-g+m5GVJWoQ2q25MVbp/jiSTjb0/qyjN6FxOb7/y4SrU=";

  # テストは無い。crates.io 由来の追加取得を避けるため check は無効化。
  doCheck = false;

  meta = {
    description = "Search backend for the ghostty quick-terminal launcher";
    homepage = "https://github.com/gapul/ghostty-launcher";
    license = lib.licenses.mit;
    mainProgram = "launcher-search";
    platforms = lib.platforms.unix;
  };
}
