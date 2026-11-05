# When you fork, editing this one file propagates everywhere.
# The attribute names of darwinConfigurations / homeConfigurations are also
# aligned to username (`just rebuild` / `nh` work as-is).
{
  # macOS username (corresponds to /Users/<username>)
  username = "gapul";

  # git commit author info
  # The email is a dedicated public alias on the own domain, not a personal inbox: it can be
  # verified on GitHub, Codeberg and git.gapul.net alike, so mirrored commits stay attributed,
  # and it survives leaving any one forge. Mail for it lands via Cloudflare Email Routing.
  # (the real address is encrypted and consolidated under pii: in secrets/common.yaml)
  gitUser = "gapul";
  gitEmail = "git@gapul.net";

  # The dotfiles' own GitHub URL (used by bootstrap.sh / nssh when cloning)
  dotfilesRepo = "https://github.com/gapul/dotfiles.git";
}
