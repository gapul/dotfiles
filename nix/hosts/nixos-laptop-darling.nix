{ pkgs, user, ... }:
# Darling, the Darwin/macOS translation layer, for running macOS command-line binaries (Xcode CLT,
# .pkg contents). GUI apps do not work in it; whole macOS goes in a quickemu VM instead.
#
# nixpkgs dropped both the package and the programs.darling module on 2025-05-11 (it vendors
# Python 2), so the package lives in pkgs/darling.nix and this file is that module inlined.
# `darling` must be setuid root: it sets up the namespaces and the overlay prefix before dropping
# privileges. The prefix defaults to ~/.darling (plus a root-owned ~/.darling.workdir next to it);
# DPREFIX moves both under the XDG data dir.
{
  home-manager.users.${user.username} =
    { config, ... }:
    {
      home.sessionVariables.DPREFIX = "${config.xdg.dataHome}/darling";
    };

  security.wrappers.darling = {
    source = "${pkgs.callPackage ../pkgs/darling.nix { }}/bin/darling";
    owner = "root";
    group = "root";
    setuid = true;
  };
}
