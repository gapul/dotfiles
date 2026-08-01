require("git"):setup()
require("full-border"):setup()

-- yamb: persistent bookmarks. Jump/add via the `u` leader (see keymap.toml).
local home = os.getenv("HOME")
require("yamb"):setup {
  jump_notify = true,
  cli = "fzf",
  -- Bookmark store must be writable: ~/.config/yazi is a read-only Nix symlink,
  -- so keep it under the (writable) XDG state dir instead.
  path = home .. "/.local/state/yazi/bookmark",
  bookmarks = {
    { tag = "dotfiles", path = home .. "/.dotfiles/",             key = "c" },
    { tag = "github",   path = home .. "/Developer/github.com/",  key = "d" },
    { tag = "notes",    path = home .. "/Documents/notes/",       key = "n" },
    { tag = "tmp",      path = home .. "/tmp/",                   key = "t" },
  },
}
