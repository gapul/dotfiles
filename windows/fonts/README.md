# Declarative font installation on Windows

Installs HackGen NF into Windows at user scope — the same idea as installing the
`font-hackgen-nerd` cask through home-manager on the Mac.

## Layout

```
windows/fonts/
├── README.md
└── apply.ps1   # downloads HackGen NF and installs it at user scope
```

## Running it

```powershell
just win-fonts            # for real
just win-fonts -DryRun    # see what it would do
```

bootstrap.ps1 runs it too, and `-SkipFonts` skips it.

## Where things land

- Files: `%LOCALAPPDATA%\Microsoft\Windows\Fonts\`
- Registry: `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts`
- No administrator rights required; user-scope installation has been supported since Windows 10
  1809.

## HackGen Console NF

It is in neither apps.json nor scoop, so apply.ps1 downloads the `HackGen_NF_v*.zip` asset from
yuru7/HackGen's latest GitHub release (through `gh release download`, falling back to the GitHub
API), extracts it and installs the `.ttf` files. If a HackGen font is already installed it does
nothing; `-SkipHackGen` skips the download.

JetBrainsMono Nerd Font, WezTerm's fallback, comes from apps.json instead.
