# GUI application plists

Restoring the settings of menubar and input utilities through home-manager activation.

Puddle is handled surgically — only the keys worth enforcing are written with
`defaults write` — so that its websites, meaning the wallpapers, and its security-scoped
bookmarks are not destroyed.

## What is managed

| App | Method | Notes |
|---|---|---|
| Puddle | Surgical writes, in `nix/home/darwin.nix` | Dynamic wallpaper. websites and bookmarks stay live and are never wholesale replaced. Only three behaviour keys are enforced: deactivateOnBattery, extendPuddleBelowMenuBar and showOnAllSpaces |

## Hiding and showing menubar icons

`NSStatusItem VisibleCC Item-*` set to false is what "hide this icon" means, and it is managed
here for Maccy. Keeping it explicit stops a rebuild's import from making hidden icons visible
again. The position keys, `NSStatusItem Preferred Position*`, are machine-specific and are
excluded.

## Restoring on a new Mac

`just rebuild`, through home-manager activation, writes Puddle's three behaviour keys. The rest
is done by hand in the GUI.

For Puddle, the wallpapers come from `puddle apply`, driven by `wallpapers` in
`~/.config/puddle/install.toml`. The shaders themselves are not in dotfiles; they are in
gapul/puddle-shaders and are unpacked into
`~/Library/Application Support/Puddle/Wallpapers/`. What stays here is only the
workspace-linked inputs, which are runtime state.

## Capturing a change

Puddle has no plist here, since it is written surgically. After changing a behaviour, edit the
`defaults write` calls inside `puddlePrefs` in `nix/modules/home/darwin-apps.nix` directly.
