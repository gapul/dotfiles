# textlint bundle for Japanese proofreading (reproducibly built)
#
# textlint's rule packages are not in nixpkgs, so we pin-build them with
# buildNpmPackage from package.json/package-lock.json. This lets the CLI and
# Neovim (nvim-lint) stop depending on imperative pnpm global installs and
# unifies everything under nix management.
#
# Rule resolution: textlint only looks at node_modules adjacent to config/cwd,
# so using it globally requires setting NODE_PATH (verified on real hardware).
# makeWrapper pins the bundled node_modules into NODE_PATH.
#
# Steps when updating dependencies:
#   1) Change the version in configs/textlint/package.json
#   2) cd configs/textlint && npm install --package-lock-only
#   3) Reflect the value from `nix run nixpkgs#prefetch-npm-deps -- package-lock.json` into npmDepsHash
{
  buildNpmPackage,
  nodejs,
  makeWrapper,
}:

buildNpmPackage {
  pname = "textlint-ja";
  version = "1.0.0";

  src = ../../configs/textlint;

  npmDepsHash = "sha256-s1AsdfLBveAZOOR+BeNaAt71FwCF/4Bs5zBaaQcqV88=";

  # No build script (just bundling rules)
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  # package.json has no bin, so do the install ourselves
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/textlint-ja
    cp -R node_modules $out/lib/textlint-ja/node_modules

    makeWrapper ${nodejs}/bin/node $out/bin/textlint \
      --add-flags "$out/lib/textlint-ja/node_modules/textlint/bin/textlint.js" \
      --set NODE_PATH "$out/lib/textlint-ja/node_modules"

    runHook postInstall
  '';

  meta = {
    description = "日本語校閲用 textlint バンドル (ja-technical-writing / ja-spacing / jtf-style / prh)";
    mainProgram = "textlint";
  };
}
