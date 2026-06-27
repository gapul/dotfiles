# 日本語校閲用 textlint バンドル (再現的に構築)
#
# textlint のルール群は nixpkgs に無いため、package.json/package-lock.json を
# もとに buildNpmPackage で固定ビルドする。これにより CLI・Neovim(nvim-lint)が
# pnpm global の命令的インストールに依存せず、nix 一元管理に統一される。
#
# ルール解決: textlint は config/cwd 隣接の node_modules しか探さないため、
# global 風に使うには NODE_PATH の指定が要る (実機検証済み)。makeWrapper で
# バンドルした node_modules を NODE_PATH に固定する。
#
# 依存更新時の手順:
#   1) configs/textlint/package.json のバージョンを変更
#   2) cd configs/textlint && npm install --package-lock-only
#   3) nix run nixpkgs#prefetch-npm-deps -- package-lock.json で得た値を npmDepsHash に反映
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

  # ビルドスクリプトは無い (ルールを束ねるだけ)
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  # package.json に bin が無いので install を自前で行う
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
