# The native Windows environment, outside WSL

The dotfiles for what runs on Windows itself: PowerShell, winget, WezTerm and so on.

## What this machine is now

This tree was written when Windows was the only OS here and Linux lived inside WSL2. That is no
longer the case: the machine dual-boots, NixOS owns the larger partition and does the day-to-day
work, and Windows is the secondary side. So `winget/apps.json` deliberately stays small — it
carries what Windows still has to provide on its own, not a mirror of the Linux environment.

Two rules follow from that, and they are why most of the old list is gone:

- Anything NixOS already provides on the same disk is not declared here twice (mpv, Bitwarden,
  Steam, LocalSend, KDE Connect and friends).
- WSL is not declared at all. Its whole purpose was Linux-on-Windows, and there is a real NixOS
  install one partition over.

The Linux side is managed through the flake, not from here.

## Layout

```
windows/
├── README.md
├── bootstrap.ps1                              # setup from nothing
├── ssh/
│   └── config                                 # hosts for Windows OpenSSH
├── profile/
│   └── Microsoft.PowerShell_profile.ps1       # $PROFILE
└── winget/
    └── apps.json                              # declarative, in winget import format
```

## First-time setup

Open PowerShell 7 (`pwsh.exe`) as administrator:

```powershell
# allow local scripts
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# clone dotfiles. git comes from winget separately, or by hand
git clone https://github.com/gapul/dotfiles.git $env:USERPROFILE\dotfiles

# run bootstrap
& $env:USERPROFILE\dotfiles\windows\bootstrap.ps1
```

## What bootstrap.ps1 does

1. If winget is missing, points you at the Microsoft Store to install it.
2. Installs everything in `winget/apps.json` with `winget import`.
3. Symlinks PowerShell's `$PROFILE` to `profile/Microsoft.PowerShell_profile.ps1`.
4. Symlinks the Windows OpenSSH config to `%USERPROFILE%\.ssh\config`.
5. Restricts the ACL on the age and SSH keys to you alone with icacls, if they exist, and warns
   if they do not.
6. Sets the global git configuration.

## What it does not do

- Decide which apps to install; that is what adding to `winget/apps.json` is for.
- Install WSL. Turning on the Windows feature is a manual step:
  - In PowerShell, `wsl --install -d Ubuntu`
  - Then, inside WSL, run `~/.dotfiles/scripts/bootstrap-wsl.sh`

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
