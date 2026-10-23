# Remapping key combinations on Windows, with AutoHotkey

Handles the combinations that SharpKeys and the Scancode Map cannot express.

| Layer | File | What it can do |
|---|---|---|
| Single physical keys, persistent | `windows/sharpkeys/` | One-to-one, such as CapsLock to Ctrl |
| Combinations, resident | `windows/autohotkey/keymap.ahk` | Emacs shortcuts such as Ctrl+A to Home, and anything context-dependent |

## Layout

```
windows/autohotkey/
├── README.md
└── keymap.ahk   # an AHK v2 script
```

## Starting it

`bootstrap.ps1` symlinks `keymap.ahk` into
`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\`, so it starts at login.

AutoHotkey itself is not installed by bootstrap: it is in neither `winget/apps.json` nor
`scoop/scoop.json`. Install AHK v2 by hand first, for example with
`winget install --exact --id AutoHotkey.AutoHotkey`; until then the Startup link does nothing.

To reload:

```powershell
just win-keymap   # applies sharpkeys and restarts AHK
```

By hand, if AHK is already resident, right-click the `.ahk` file and choose Run Script, or
right-click AHK in the tray and choose Reload Script.

## What it does

### 1. The Copilot key to Right Ctrl, as insurance for machines where a scancode remap cannot

The dedicated Copilot key behaves differently by vendor:

| Machine | What it sends | Handled by |
|---|---|---|
| Some HP models | The extended scancode `0xE0 0x5C` | SharpKeys, through the Scancode Map |
| Lenovo, and some 24H2 machines | The key sequence `LShift + LWin + F23` | Not remappable by scancode, so AHK |

To find out which one you have: with AHK running, right-click the tray icon, then Open, View,
Key history; press the Copilot key; read the scancode from the log; and switch the Copilot line
in `keymap.ahk` to whichever matches.

### 2. Bringing back the Emacs shortcuts

macOS gives you Emacs bindings in every Cocoa text field as standard. Windows does not, so AHK
emulates them.

| Key | What it does |
|---|---|
| `Ctrl+A` | Start of line, Home |
| `Ctrl+E` | End of line, End |
| `Ctrl+B` | One character left |
| `Ctrl+F` | One character right |
| `Ctrl+P` | One line up |
| `Ctrl+N` | One line down |
| `Ctrl+H` | Delete the character before |
| `Ctrl+D` | Delete the character after |
| `Ctrl+K` | Kill to end of line |

#### Where they are switched off

- Terminals: `ConsoleWindowClass`, `CASCADIA_HOSTING_WINDOW_CLASS`, `WezTermWindow`, `mintty`
- Editors: Vim, VS Code, Cursor, nvim, Hyper

In those, the original meanings — Ctrl+A as select all, and so on — are respected. They are
matched on window class or process name.

### Customising it

Add to `EmacsExcludeClasses` or `EmacsExcludeProcesses` to disable the Emacs bindings in another
app:

```ahk
EmacsExcludeProcesses := "i)^(WezTerm|wt|alacritty|Code|MyApp)\.exe$"
```

## If an antivirus blocks it

AHK uses a low-level keyboard hook, `SetWindowsHookEx WH_KEYBOARD_LL`, so third-party antivirus
heuristics sometimes treat it as a keylogger and block it: it starts, disappears a few seconds
later, and never shows a tray icon. No such product is declared here any more (Bitdefender was
dropped from apps.json); if one is installed by hand, add exceptions for
`C:\Users\<user>\dotfiles\windows\autohotkey\` and `C:\Program Files\AutoHotkey\`, and an
application exception for AutoHotkey64.exe if it has a separate behavioural layer.
