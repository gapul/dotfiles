# Vim-style keys in terminal-browser (a stand-in for Surfingkeys)

terminal-browser cannot load extensions. It does not expose Electron's
`session.loadExtension`, so there is no path by which Surfingkeys could be installed at all.
What follows is an equivalent written in two layers.

| | Where it goes | Equivalent to |
| --- | --- | --- |
| `configs/cli/terminal-browser/vimkeys.js` | `--preload`, the page's isolated world | content script |
| `configs/cli/terminal-browser/main.js` | `--main-script`, the Electron main process | background script |

`--main-script` is loaded as `createRequire(file)(file)`, so it is plain CommonJS and
`require("electron")` works directly. The page side has `ipcRenderer`, so only the operations a
page cannot reach are forwarded to the main process.

The wiring lives in the bin wrapper in `nix/pkgs/terminal-browser.nix`. It adds the two flags
only for `open` and `new-tab`; `--preload` is accepted by those two alone and crashes
`shutdown` or `ls`. Neither file is required — if either is missing nothing is added, so
deleting them returns you to stock terminal-browser.

## What is implemented

Built by working through Surfingkeys' default mappings
(`src/content_scripts/common/default.js`, 145 of them) alongside the scrolling code in
`normal.js`.

Scrolling: `j` `k` `h` `l` `d` `u` `gg` `G` `0` `$` `;fs`
Hints: `f` `af` `gf` `cf` `q` `ya` `yma` `yv` `ymv` `yc` `yq` `yi` `i` `gi` `O`
History and URLs: `S` `D` `r` `gu` `gU` `g?` `g#` `[[` `]]`
Yank: `yy` `yh` `yl` `ys` `yf` `yp` `gs`
Visual and search: `v` `V` `zv` `n` `N` `*` `/`, and inside visual mode `h` `j` `k` `l` `w` `b` `0` `$` `y`
Marks: `m<char>` `'<char>`
Zoom: `zi` `zo` `zr`
Tabs, through main.js: `x` `X` `on` `t` `go` `yt` `yT` `gxx` `gxt` `gxT`
Other: `.` `?` `Esc`

`?` shows this list on screen.

## What is not reproduced

### Nothing to bind to

These reach into Chrome-specific surfaces. terminal-browser has no bookmarks, no history
database, no download shelf, no extension mechanism, no session restore and no proxy settings,
so there is nothing on the other end.

- Bookmarks: `b` `ab` `;db` `gb`
- History: `oh` `ox` `;dh` `;yh` `;ph` `gh`
- Downloads: `yd` `;di` `;j` `gd`
- Anything opening `chrome://`: `ga` `gc` `gk` `ge` `gn` `;i`
- Extension list: `ge`
- Proxy: `cp` `;cp` `;ap`
- Sessions: `ZZ` `ZR`
- Container tabs `;cl` and incognito `oi`
- Window management: `W` `;gt` `;gw`. A terminal-browser window is a pane.

### No public entry point

terminal-browser's tab model lives in an internal class and its ordering cannot be touched from
outside. The CLI (`terminal-browser new-tab`) is the only public way in, so adding, closing and
duplicating go through it. Selection and reordering belong to terminal-browser's own tab keys
and palette, so rather than fake an implementation these report that instead.

- `gt` `gT` `<<` `>>` `T` `<Ctrl-6>` `gp` `B` `F` `;x` `gx0` `gx$` `gxp`

### Needs an external service or a separate process

- Translation and LLMs: `Q` `;t` `A` `<Space>t` `cq` `gr`
- vim and neovim integration: `<Ctrl-i>` `<Ctrl-Alt-i>` `;v` `;u` `;U` `I`
- PDF viewer: `;s`
- Markdown preview: `;pm`
- Editing settings, and yanking or putting them: `;e` `yj` `;pj` `yQ`

### Left out on purpose

- `w` (switch frame) and `;w` (go to the top frame). Crossing iframes is hard to picture in a
  single pane inside a terminal.
- `<Ctrl-h>` and `<Ctrl-j>`, which fire mouseover and mouseout. Modified keys collide with
  terminal-browser's own shortcuts, so the rule here is to watch unmodified keys only.
- Anything that reads the clipboard, such as `;pp`, `cc` and `;ap`. Reading requires
  `--allow-clipboard-read`, and leaving that off is a deliberate choice that wins here.

## Adding your own

One line in `CMD` in `~/.config/terminal-browser/vimkeys.js` is enough. No rebuild — it applies
the next time you open a page. Once a binding sticks, move it into
`configs/cli/terminal-browser/vimkeys.js`.
