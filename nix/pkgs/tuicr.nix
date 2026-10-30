{
  lib,
  rustPlatform,
  fetchFromGitHub,
  git,
}:
rustPlatform.buildRustPackage {
  pname = "tuicr";
  version = "0.28.0";

  src = fetchFromGitHub {
    owner = "agavra";
    repo = "tuicr";
    tag = "v0.28.0";
    hash = "sha256-Q1VcRGTN3BO/UYTY0/SBN05v/0Dy+iEUNFshHoBjNVM=";
  };

  cargoHash = "sha256-+HbzMHq3OCuF+RCGXaLSbN4+xcFTYyKUI54advFKcEU=";
  strictDeps = true;
  nativeCheckInputs = [ git ];
  checkFlags = [
    "--skip=should_return_no_changes_for_clean_repo"
    # Wall-clock assertion (~150ms) that fails on a loaded builder.
    "--skip=should_fetch_pr_file_list_and_patch_concurrently"
  ];

  meta = {
    description = "Review AI-generated diffs like a GitHub pull request in the terminal";
    homepage = "https://tuicr.dev";
    changelog = "https://github.com/agavra/tuicr/blob/v0.28.0/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "tuicr";
    platforms = lib.platforms.unix;
  };
}
