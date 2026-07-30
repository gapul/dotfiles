_:
# Development environment (imported only on nixos-laptop).
# System features like podman go in hosts/nixos-laptop.nix; user-oriented ones go here.
{
  # direnv + nix-direnv: automatically enable a dev shell (flake/shell.nix) per directory.
  # zsh integration is picked up by the zsh config in home/common.nix (programs.direnv installs the hook).
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true; # fast-cache flake devShell
  };
}
