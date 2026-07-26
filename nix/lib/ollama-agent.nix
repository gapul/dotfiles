# ollama serve を LaunchAgent で常駐させる共通 launch 仕様の SSO。
#
# workstation (home-manager: modules/home/darwin-services.nix の launchd.agents.ollama.config)
# と macmini (nix-darwin: hosts/macmini.nix の launchd.agents.ollama.serviceConfig) が共有する。
# 両者は module 系が違い、log パス・EnvironmentVariables・ProcessType が異なるので、
# 差分は呼び出し側で `// { ... }` して付ける。ここでは起動コマンド本体だけを束ねる。
{ pkgs }:
{
  ProgramArguments = [
    "${pkgs.ollama}/bin/ollama"
    "serve"
  ];
  RunAtLoad = true;
  KeepAlive = true;
}
