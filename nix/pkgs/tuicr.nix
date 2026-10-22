{
  lib,
  rustPlatform,
  fetchFromGitHub,
  git,
}:
rustPlatform.buildRustPackage {
  pname = "tuicr";
  version = "0.27.0";

  src = fetchFromGitHub {
    owner = "agavra";
    repo = "tuicr";
    tag = "v0.27.0";
    hash = "sha256-kObt0MLJZYASWM1vexZTPaIeFaU2XpT9sHUSdClRz2Y=";
  };

  cargoHash = "sha256-azgmxJP3iQO+WfJCWqfi19rCSb6D0a0luWcgEW+8Sbg=";
  strictDeps = true;
  nativeCheckInputs = [ git ];
  checkFlags = [ "--skip=should_return_no_changes_for_clean_repo" ];

  meta = {
    description = "Review AI-generated diffs like a GitHub pull request in the terminal";
    homepage = "https://tuicr.dev";
    changelog = "https://github.com/agavra/tuicr/blob/v0.27.0/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "tuicr";
    platforms = lib.platforms.unix;
  };
}
