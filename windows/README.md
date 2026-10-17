# The native Windows environment, outside WSL

The dotfiles for what runs on Windows itself: PowerShell, winget, WezTerm and so on.

## What this machine is now

This tree was written when Windows was the only OS here and Linux lived inside WSL2. That is no
longer the case: the machine dual-boots, NixOS owns the larger partition and does the day-to-day
work, and Windows is the secondary side. So `winget/apps.json` deliberately stays small — it
carries what Windows still has to provide on its own, not a mirror of the Linux environment.

Two rules follow from that, and they are why most of the old list is gone:

- Anything NixOS already provides on the same disk is not declared here twice (mpv, Steam,
  KDE Connect and friends).
- WSL is not declared at all. Its whole purpose was Linux-on-Windows, and there is a real NixOS
  install one partition over.

The Linux side is managed through the flake, not from here.

## Layout

```
windows/
├── README.md
├── SETUP-CHECKLIST.md          # the first-time setup on a machine, step by step
├── bootstrap.ps1               # setup from nothing; runs the apply scripts below
├── PSScriptAnalyzerSettings.psd1
├── winget/                     # apps.json (winget import format), verify.ps1, status.ps1
├── scoop/                      # the fallback for what winget does not carry
├── profile/                    # $PROFILE for PowerShell 7 and 5.1
├── ssh/                        # hosts for Windows OpenSSH
├── privacy/                    # telemetry and preinstalled apps: Win11Debloat, WinUtil, baseline
├── sharpkeys/                  # key remapping through the Scancode Map
├── autohotkey/                 # the AHK keymap, started from the Startup folder
├── locale/                     # language list, system locale, home location
├── fonts/                      # user-scope install of configs/fonts/
├── theme/                      # renders the palette into the zebar, GlazeWM and Terminal configs
└── tasks/                      # GlazeWM autostart through Task Scheduler
```

## First-time setup

Follow `SETUP-CHECKLIST.md`. In short, from an administrator PowerShell:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
git clone https://github.com/gapul/dotfiles.git $env:USERPROFILE\dotfiles
& $env:USERPROFILE\dotfiles\windows\bootstrap.ps1
```

## What bootstrap.ps1 does

It is idempotent, and `-DryRun` shows the plan without side effects.

1. Checks winget, and installs PowerShell 7 first, because the profile needs PSReadLine 2.2+.
2. Installs `winget/apps.json` with `winget import`, then applies `scoop/scoop.json`
   (`-SkipScoop`).
3. Symlinks `$PROFILE`, for both PowerShell 7 and 5.1.
4. Symlinks tool configs from `configs/`: the SSH config, Zed, espanso, WezTerm, GlazeWM and
   zebar.
5. Restricts the ACL on the age and SSH keys to you alone with icacls, if they exist, and sets
   up the ssh-agent service (or, with `-UseBitwardenSSH`, disables it in favour of Bitwarden's).
6. Sets the global git configuration.
7. Applies `privacy/` (`-SkipPrivacy`); see `privacy/README.md`.
8. Applies the keymap, SharpKeys and AutoHotkey (`-SkipKeymap`), renders the theme, and installs
   the fonts (`-SkipFonts`).
9. Applies the locale and language settings (`-SkipLocale`).

Each step also has its own `just win-*` recipe for running it alone.

## What it does not do

- Decide which apps to install; that is what adding to `winget/apps.json` is for.
- Install WSL. On the dual-boot machine there is no reason to, and nothing here needs it. The
  WSL pieces that remain (`-WslUser`, the ssh-agent relay in `nix/home/wsl.nix`,
  `docs/NIXOS_WSL.md`) are kept for a Windows-only machine; there, WSL is a manual step:
  `wsl --install -d Ubuntu`, then `~/.dotfiles/scripts/bootstrap-wsl.sh` inside it.

## winget and scoop

winget comes first. Both CLIs and GUI apps are normally declared by adding them to `apps.json`.

scoop is the fallback, only for things winget's repository does not carry: legacy tools and
things distributed only as portables.

If the same tool arrives from both, whichever comes first in PATH wins. `Find-DotfilesToolOverlap`,
defined in profile.ps1, lists the duplicates. When there is one, the rule is to remove the scoop
copy with `scoop uninstall <tool>` and standardise on winget.

## Applying changes

For the PowerShell profile, edit the file and reload with `. $PROFILE`.

For WezTerm, edit the configuration and restart it.
