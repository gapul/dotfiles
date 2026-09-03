# Remapping physical keys on Windows

The key-remapping half of Karabiner-Elements, reproduced on Windows. It uses the same mechanism
SharpKeys does — `HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout\Scancode Map` — but
writes it declaratively from PowerShell, without needing the SharpKeys GUI.

## Layout

```
windows/sharpkeys/
├── README.md
├── keymap.skl   # human-readable SharpKeys format, for reference; the real source is the $Mappings array in apply.ps1
└── apply.ps1    # builds the Scancode Map and writes it to the registry
```

## Running it

```powershell
# apply. Needs administrator rights, and takes effect after a reboot
just win-keymap

# check without side effects
just win-keymap -DryRun

# remove every remap and return to the standard layout
just win-keymap -Clear
```

bootstrap.ps1 runs it as step 8. To skip it:

```powershell
pwsh -File windows/bootstrap.ps1 -SkipKeymap
```

## What is remapped

| Mapping | State |
|---|---|
| CapsLock to Left Ctrl | Applied, scancode 0x3A to 0x1D |
| The Copilot key to Right Ctrl | Waiting on a scancode from the real machine |

## Finding the Copilot key's scancode

The dedicated Copilot key on Windows 11 OEM machines differs by vendor:

- Some HP machines send the extended scancode `0xE0 0x5C`.
- Lenovo sends a Win+Shift+F23 sequence, which cannot be remapped at the scancode level.
- Others send `vk89`, `F23` and similar.

To find out, use AutoHotkey's Key History:

1. With the AHK script running, press the Copilot key.
2. Right-click AHK in the tray, then Open, View, "Key history and script info".
3. Read the scancode out of the log.

If it turns out to be something like `E0 5C`, enable it in `$Mappings` in `apply.ps1`:

```powershell
@{ Source = 'E05C'; Dest = 'E01D'; Comment = 'Copilot -> Right Ctrl' }
```

If it is a combination such as `LSHIFT+LWIN+F23`, no scancode remap can catch it, and it has to
be handled on the AHK side, as `+#F23::RControl`.

## Combinations are a different layer

SharpKeys and the Scancode Map only do one-to-one remapping of single keys. The Emacs
shortcuts, such as Ctrl+A to Home, are implemented in `windows/autohotkey/keymap.ahk`.

## Excluding it from Bitdefender

Because `apply.ps1` writes
`HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout\Scancode Map` directly, Bitdefender's
heuristics sometimes quarantine it. Add the directory under Bitdefender Security Center,
Protection, Antivirus, Settings, Manage Exceptions:

```
C:\Users\<user>\dotfiles\windows\sharpkeys\
```

If it has already been quarantined, restore it from Bitdefender, Notifications, Quarantine, add
the exception above, and run `just win-keymap` again.
