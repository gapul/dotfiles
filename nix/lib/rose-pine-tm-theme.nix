# Rosé Pine's TextMate themes, straight from upstream. `dist/rose-pine.tmTheme` and
# `dist/rose-pine-dawn.tmTheme`.
#
# One pin, two consumers: bat registers them in its cache (modules/home/cli.nix) and codex reads
# its own copy (modules/home/agents.nix). They were committed under configs/cli/bat/themes/
# before — the dark one byte-identical to upstream, the light one generated from it by palette
# substitution, which left it carrying the dark theme's name and uuid. Upstream publishes both.
{ pkgs }:
pkgs.fetchFromGitHub {
  owner = "rose-pine";
  repo = "tm-theme";
  rev = "6d556734541ccb04172e81fd58de4a35fff72d19";
  hash = "sha256-5+fG21KbB7bdPvszkz9Ftl6fCDGs17fJNTAXFRFWZGo=";
}
