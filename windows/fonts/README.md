# Declarative font installation on Windows

Installs every `.ttf` and `.otf` under `configs/fonts/` into Windows at user scope — the same
idea as installing `font-*` casks through home-manager on the Mac.

## Layout

```
windows/fonts/
├── README.md
└── apply.ps1   # installs configs/fonts/*.ttf and *.otf at user scope
```

## Running it

```powershell
just win-fonts            # for real
just win-fonts -DryRun    # see what it would do
just win-fonts -Force     # overwrite what is already there
```

bootstrap.ps1 runs it too, and `-SkipFonts` skips it.

## Where things land

- Files: `%LOCALAPPDATA%\Microsoft\Windows\Fonts\`
- Registry: `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts`
- No administrator rights required; user-scope installation has been supported since Windows 10
  1809.

## What it is mainly for

`sketchybar-app-font.ttf`, which Zebar's bar.html uses to turn a process name into an
`:app_name:` ligature for the focused app icon, reproducing the icon mapping SketchyBar uses on
the Mac.

## HackGen Console NF

It is in neither apps.json nor scoop, so download the `.zip` from yuru7/HackGen's GitHub
releases, extract it, and drop the fonts into `configs/fonts/`; apply.ps1 installs them from
there.

```powershell
# find the HackGen_NF release asset
$url = (gh release view --repo yuru7/HackGen --json assets --jq '.assets[] | select(.name | contains("NF")) | .url' | Select-Object -First 1)
# then download, extract and copy into configs/fonts/ by hand
```
