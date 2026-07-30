# When you fork, editing this one file propagates everywhere.
# The attribute names of darwinConfigurations / homeConfigurations are also
# aligned to username (`just rebuild` / `nh` work as-is).
{
  # macOS username (corresponds to /Users/<username>)
  username = "gapul";

  # git commit author info
  # The email uses GitHub noreply to avoid exposing a personal address on public repos.
  # (the real address is encrypted and consolidated under pii: in secrets.yaml)
  gitUser = "gapul";
  gitEmail = "92638132+gapul@users.noreply.github.com";

  # The dotfiles' own GitHub URL (used by bootstrap.sh / nssh when cloning)
  dotfilesRepo = "https://github.com/gapul/dotfiles.git";
}
