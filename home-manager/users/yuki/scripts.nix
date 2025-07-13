# User scripts configuration
# Web development template tools integration
{ lib, pkgs, ... }:

{
  # Web development template tools
  home.file."bin/web-create" = {
    source = ../../scripts/web-create.sh;
    executable = true;
  };
  
  home.file."bin/template-manager" = {
    source = ../../scripts/template-manager.sh;
    executable = true;
  };
  
  # Add to PATH
  home.sessionPath = [
    "$HOME/bin"
  ];
}