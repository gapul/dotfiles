{ user, ... }:
{
  # One source for "which keys may log in as me", shared by NixOS and darwin hosts.
  #
  # hosts/homeserver.nix used to say the quiet part out loud:
  #
  #   Keys are not declared here: they live in the Bitwarden-managed agent, and this repo is
  #   public. Add them by hand
  #
  # That was the last hand-managed piece of access control in an otherwise declarative setup, and
  # hand-managed means revocation never actually happens — removing a key from a machine you no
  # longer own is a chore nobody does. Declaring it makes adding and removing a key the same
  # one-line edit, applied on the next rebuild.
  #
  # The keys are committed in the clear rather than kept in sops. A public key is not a credential:
  # holding it grants nothing, which is why we hand it to every server in the first place. What it
  # does leak is the shape of the fleet, and that is the same tradeoff already accepted for
  # nix/keys/ssh-user-ca.pub. If that turns out to be the wrong call, moving the file back behind
  # sops is a two-line revert.
  #
  # nix-darwin implements this as /etc/ssh/nix_authorized_keys.d/<user> plus an
  # AuthorizedKeysCommand, so it works the same on both platforms without touching ~/.ssh.
  users.users.${user.username}.openssh.authorizedKeys.keyFiles = [ ../keys/authorized_keys ];
}
