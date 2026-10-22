# Neovim

A LazyVim-based config. `nix/modules/home/editor.nix` links this directory to `~/.config/nvim`
as an out-of-store symlink, so edits land straight in the repo.

Most plugins are not fetched at runtime: `lazy2nix/` turns `lazy-lock.json` into a nix bundle,
exposed as `$LAZY_NIX_PLUGINS` and read by `lua/config/lazy.lua`. After changing the lock file,
run `nix run ./nix#lazy2nix` to regenerate it. Plugins excluded in `lazy2nix/config.json` stay
with lazy.nvim.
