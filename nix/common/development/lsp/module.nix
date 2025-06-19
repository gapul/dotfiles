# LSP Module Integration
{ config, lib, pkgs, ... }:

{
  imports = [
    ./default.nix
    ./performance.nix
    ./auto-config.nix
  ];
}