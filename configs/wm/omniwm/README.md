# OmniWM configuration

This is the real `~/.config/omniwm/settings.toml`, linked in as an out-of-store symlink, so
changing a setting through OmniWM's GUI rewrites this file directly.

The configuration is not generated from nix. OmniWM writes it back itself — keys sorted, floats
at full precision, and keys appearing and disappearing across versions — and a read-only
symlink into the store cannot be saved to. An out-of-store symlink means those writes land in
the repository.

The wiring is in `nix/home/darwin.nix`, so a rebuild on a new Mac creates the link. Changes show
up in `git diff` whenever the GUI is touched, and can simply be committed.

If OmniWM writes through a temporary file and a rename, the symlink is replaced by a real file
and tracking breaks. The next rebuild leaves a `.hm-bak` behind, which is how you notice: the
change is lost but the file is intact.
