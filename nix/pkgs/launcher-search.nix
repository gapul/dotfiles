# Search backend for ghostty-launcher (Rust).
# Previously it was `cargo build --release`d inside the repo and referenced via a
# core/launcher-search symlink, but the output target/ got swept up by `just gc-deep`'s
# "rust targets untouched for 30 days" cleanup and vanished, making the launcher unable to start.
# Building into the nix store and pointing at it via LAUNCHER_SEARCH_BIN protects it as a GC root
# and regenerates it on every `nh home switch` (no target/ needed).
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

  # The crate is not at the repo root but in the launcher-search/ subdirectory.
  cargoRoot = "launcher-search";
  buildAndTestSubdir = "launcher-search";

  cargoHash = "sha256-g+m5GVJWoQ2q25MVbp/jiSTjb0/qyjN6FxOb7/y4SrU=";

  # No tests. Disable check to avoid extra crates.io fetches.
  doCheck = false;

  meta = {
    description = "Search backend for the ghostty quick-terminal launcher";
    homepage = "https://github.com/gapul/ghostty-launcher";
    license = lib.licenses.mit;
    mainProgram = "launcher-search";
    platforms = lib.platforms.unix;
  };
}
