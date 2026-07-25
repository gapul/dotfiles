{
  lib,
  rustPlatform,
  fetchFromGitHub,
  git,
}:
rustPlatform.buildRustPackage {
  pname = "tuicr";
  version = "0.19.1";

  src = fetchFromGitHub {
    owner = "agavra";
    repo = "tuicr";
    tag = "v0.19.1";
    hash = "sha256-uLtwpieKBTbLLDmgE4LLNljvv69i0cBRvU1WEgy09Xo=";
  };

  cargoHash = "sha256-jEPgXXlqTgVX+GutQX8JCwtLS0J3cx7RV76NdM5m6QE=";
  strictDeps = true;
  nativeCheckInputs = [ git ];
  checkFlags = [ "--skip=should_return_no_changes_for_clean_repo" ];

  meta = {
    description = "Review AI-generated diffs like a GitHub pull request in the terminal";
    homepage = "https://tuicr.dev";
    changelog = "https://github.com/agavra/tuicr/blob/v0.19.1/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "tuicr";
    platforms = lib.platforms.unix;
  };
}
