{ lib, user, ... }:
# No ~/.zshenv on the laptop. home/common.nix writes one on every host because zsh only reads
# $ZDOTDIR/.zshenv once something has set ZDOTDIR; here the system zshenv sets it instead, and
# the exports that file carried move into $ZDOTDIR/.zshenv. /etc/zshenv runs for every zsh
# (its once-only guard is a plain shell variable, not exported), and $HOME/.config/zsh only
# exists for users with this home-manager config, so root and others keep zsh's defaults.
let
  xdgEnv = import ../lib/shell-xdg-env.nix;
in
{
  programs.zsh.shellInit = ''
    if [ -z "''${ZDOTDIR-}" ] && [ -d "$HOME/.config/zsh" ]; then
      export ZDOTDIR="$HOME/.config/zsh"
    fi
  '';

  home-manager.users.${user.username} = {
    home.file.".zshenv".enable = lib.mkForce false;
    programs.zsh.envExtra = lib.mkAfter (xdgEnv.guardless + "\n");
  };
}
