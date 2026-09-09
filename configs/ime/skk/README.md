# SKK: macSKK, skkeleton and the azooKey skkserv

## The pieces

| Piece | Where | Role |
|---|---|---|
| macSKK | An input method, sandboxed in a container | Japanese input in GUI applications |
| skkeleton | An nvim plugin | SKK inside the editor |
| azooKey skkserv | `/Applications/azooKey skkserv.app` | An skkserv on localhost:1178 |
| Public dictionaries | `~/.skk/SKK-JISYO.{L,geo,jinmei,propernoun,station}` | Read directly by skkeleton |
| Public dictionaries, macSKK's copy | `~/Library/Containers/net.mtgto.../Documents/Dictionaries/` | What macSKK can read from inside its sandbox |
| User dictionary, macSKK | `skk-jisyo.utf8` in the same place | macSKK's own learning |
| User dictionary, skkeleton | `~/.skk/skkeleton-user-dict` | skkeleton's own learning |

## What dotfiles manages

- `macSKK.plist` — macSKK's workarounds for Ghostty and VS Code, its UI settings, and the
  skkserv connection details.
- `azoo-key-skkserv.plist` — host, incomingCharset and startServerAtLaunch.
- `kana-rule.conf` — the romaji conversion rules, aligned with skkeleton's handling of
  punctuation: `！`, `？` and `：` become full width, `（）` stay half width, and
  `#!use-default` inherits the rest.

The two plists are applied by `home.activation.skkPlistImport` in home.nix, through
`defaults import` followed by `killall cfprefsd` to flush.

`kana-rule.conf` is not a plist but a file inside the container's Documents, so
`home.activation.skkKanaRule` copies it in with `install`. As with the dictionaries, a symlink
does not work.

## What the sandbox will not allow

1. **Dictionaries cannot be symlinked.** macSKK's sandbox cannot read a symlink into `~/.skk/`;
   it gets NSPOSIX EPERM. A real copy is required, which means keeping 9 MB twice.
2. **Writing the plist directly does not work.** macSKK does not load the `dictionaries[]`
   array at startup; it registers them from runtime events through NSFilePresenter. Even
   `defaults import` will not reproduce the dictionary list.
3. **Registering a dictionary is a manual step.** With macSKK running, the file has to be
   deleted and put back to fire the NSFilePresenter event.

## First-time setup on a new Mac

```bash
# 1. put the public dictionaries in ~/.skk/, for skkeleton
bash ~/.dotfiles/scripts/install-skk-dicts.sh

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
# extract macSKK's plist and convert it to XML, so git diff is readable
cp ~/Library/Containers/net.mtgto.inputmethod.macSKK/Data/Library/Preferences/net.mtgto.inputmethod.macSKK.plist \
   ~/.dotfiles/configs/ime/skk/macSKK.plist
plutil -convert xml1 ~/.dotfiles/configs/ime/skk/macSKK.plist

# extract azooKey skkserv's plist, drop the UI state, convert to XML
cp ~/Library/Containers/io.github.gitusp.azoo-key-skkserv/Data/Library/Preferences/io.github.gitusp.azoo-key-skkserv.plist \
   ~/.dotfiles/configs/ime/skk/azoo-key-skkserv.plist
python3 -c "
import plistlib
p = '$HOME/dotfiles/configs/ime/skk/azoo-key-skkserv.plist'
with open(p, 'rb') as f: d = plistlib.load(f)
for k in list(d):
    if k.startswith('NSWindow Frame'): del d[k]
with open(p, 'wb') as f: plistlib.dump(d, f)
"
plutil -convert xml1 ~/.dotfiles/configs/ime/skk/azoo-key-skkserv.plist
```

`defaults import` accepts both XML and binary, so keeping the dotfiles copy as XML is fine.
macSKK writing binary back through its GUI does not matter, because converting again at capture
time keeps the history clean.

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
