# SSO of the common launch spec for keeping ollama serve resident via LaunchAgent.
#
# Shared by workstation (home-manager: launchd.agents.ollama.config in modules/home/darwin-services.nix)
# and macmini (nix-darwin: launchd.agents.ollama.serviceConfig in hosts/macmini.nix).
# The two use different module systems and differ in log path / EnvironmentVariables / ProcessType,
# so the caller adds the differences via `// { ... }`. Here we only bundle the launch command itself.
{ pkgs }:
{
  ProgramArguments = [
    "${pkgs.ollama}/bin/ollama"
    "serve"
  ];
  RunAtLoad = true;
  KeepAlive = true;
}
