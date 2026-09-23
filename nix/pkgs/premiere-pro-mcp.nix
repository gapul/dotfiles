# premiere-pro-mcp: MCP server that drives Adobe Premiere Pro through its CEP bridge panel.
# Adobe ships no official one; this community server was a hand build in ~/Developer.
#
# Pinned to v1.13.0, the version whose CEP panel is installed and was verified against Premiere
# 26.3. The server and the panel talk over their own bridge protocol, so bumping this means
# re-running `premiere-pro-mcp --install-cep` with Premiere open and checking
# verify_premiere_connection. The npm registry copy lags (1.9.2), hence the GitHub tag.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage (finalAttrs: {
  pname = "premiere-pro-mcp";
  version = "1.13.0";

  src = fetchFromGitHub {
    owner = "leancoderkavy";
    repo = "premiere-pro-mcp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Epvc7bBN4odlAgl9cYtf3i/yGIf/HcInS7tVYoW+AOc=";
  };

  npmDepsHash = "sha256-B+DGxSVRjeeHGKUBhvjKsdaObNOL+WDU5U0IsHehCyo=";

  meta = {
    description = "MCP server for Adobe Premiere Pro";
    homepage = "https://github.com/leancoderkavy/premiere-pro-mcp";
    license = lib.licenses.mit;
    mainProgram = "premiere-pro-mcp";
    platforms = lib.platforms.darwin;
  };
})
