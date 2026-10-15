{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage {
  pname = "agent-access";
  version = "0.11.0";

  src = fetchFromGitHub {
    owner = "bitwarden";
    repo = "agent-access";
    tag = "v0.11.0";
    hash = "sha256-rBt7KwzzkDruOUECvDk845eH9rHjXg+6MOwC8U1cozA=";
  };

  # Local: AAC_APPROVAL_COMMAND lets `aac listen` approve credential requests by running a command
  # (macmini: aac-matrix-approve, a ✅ reaction in Matrix) and turns keyboard approval off while it
  # is set, so tmux send-keys from an agent cannot approve. Unset, behaviour is upstream's.
  patches = [ ./agent-access-approval-command.patch ];

  cargoHash = "sha256-jNE5ozp6YW1dlx948KfvNAZ8/ZPPvSYeRc89WGSy5HI=";
  strictDeps = true;
  # Only the CLI; the workspace also holds the relay, uniffi bindings and examples.
  cargoBuildFlags = [
    "-p"
    "ap-cli"
  ];
  cargoTestFlags = [
    "-p"
    "ap-cli"
  ];

  meta = {
    description = "Hand AI agents single vault credentials on human approval (Bitwarden Agent Access CLI)";
    homepage = "https://github.com/bitwarden/agent-access";
    license = lib.licenses.asl20;
    mainProgram = "aac";
    platforms = lib.platforms.unix;
  };
}
