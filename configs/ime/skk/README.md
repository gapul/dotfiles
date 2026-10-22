# SKK: macSKK, skkeleton and the azooKey skkserv

## The pieces

| Piece | Where | Role |
|---|---|---|
| macSKK | An input method, sandboxed in a container | Japanese input in GUI applications |
| skkeleton | An nvim plugin | SKK inside the editor |
| azooKey skkserv | `/Applications/azooKey skkserv.app` | An skkserv on localhost:1178 |
| Public dictionaries | `~/.local/share/skk/SKK-JISYO.{L,geo,jinmei,propernoun,station}` | Placed by nix (`nix/modules/home/editor.nix`), read directly by skkeleton |
| Public dictionaries, macSKK's copy | `~/Library/Containers/net.mtgto.../Documents/Dictionaries/` | What macSKK can read from inside its sandbox |
| User dictionary, macSKK | `skk-jisyo.utf8` in the same place | macSKK's own learning |
| User dictionary, skkeleton | `~/.local/share/skk/skkeleton-user-dict` | skkeleton's own learning |

## What dotfiles manages

- `macSKK.plist` — macSKK's workarounds for Ghostty and VS Code, its UI settings, and the
  skkserv connection details.
- `azoo-key-skkserv.plist` — host, incomingCharset and startServerAtLaunch.
- `kana-rule.conf` — the romaji conversion rules, aligned with skkeleton's handling of
  punctuation: `！`, `？` and `：` become full width, `（）` stay half width, and
  `#!use-default` inherits the rest.

The two plists are applied by `home.activation.skkPlistImport` in
`nix/modules/home/darwin-apps.nix`, through `defaults import` followed by `killall cfprefsd` to
flush.

`kana-rule.conf` is not a plist but a file inside the container's Documents, so
`home.activation.skkKanaRule` copies it in with `install`. As with the dictionaries, a symlink
does not work.

## What the sandbox will not allow

1. **Dictionaries cannot be symlinked.** macSKK's sandbox cannot read a symlink into
   `~/.local/share/skk/`; it gets NSPOSIX EPERM. A real copy is required, which means keeping
   9 MB twice.
2. **Writing the plist directly does not work.** macSKK does not load the `dictionaries[]`
   array at startup; it registers them from runtime events through NSFilePresenter. Even
   `defaults import` will not reproduce the dictionary list.
3. **Registering a dictionary is a manual step.** With macSKK running, the file has to be
   deleted and put back to fire the NSFilePresenter event.

## First-time setup on a new Mac

```bash
# 1. nix already places the public dictionaries in ~/.local/share/skk/, for skkeleton
#    (nix/modules/home/editor.nix), so there is nothing to run for this step

# 2. start macSKK once, by switching to Japanese input from the menu bar,
#    and wait for its container directory to be created

# 3. copy the dictionaries into macSKK's container too.
#    With macSKK running, delete and ditto them in, to fire NSFilePresenter.
bash ~/.dotfiles/scripts/install-skk-dicts-macskk.sh

# 4. in macSKK's settings, under Dictionaries, toggle each dictionary on

# 5. optionally enable skkserv, in macSKK's settings under Dictionaries
```

## Capturing a change

After changing macSKK or skkserv through their GUIs, get it back into dotfiles with:

```bash
just plist-sync
```

It updates only the keys the repo plists already track, so window frames and other UI state stay
out. To track a new key, add it to the repo plist once with `plutil -insert`. Review the diff
before committing.

After changing kana-rule, which is a real file, a plain copy is enough:

```bash
cp ~/Library/Containers/net.mtgto.inputmethod.macSKK/Data/Documents/Settings/kana-rule.conf \
   ~/.dotfiles/configs/ime/skk/kana-rule.conf
```

## What is not shared

**Learning history**, the user dictionaries, is separate between macSKK and skkeleton. Sharing
them is a problem for another day: pointing both at one file risks losing it to a race, and the
formats are not guaranteed compatible.

**macSKK's list of dictionary files** has to be toggled through the GUI each time, since it
cannot be reproduced through the plist.
