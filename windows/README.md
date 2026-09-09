# The native Windows environment, outside WSL

The dotfiles for what runs on Windows itself: PowerShell, winget, WezTerm and so on. The Linux
side inside WSL2 is managed separately, through `~/.dotfiles/nix/home/wsl.nix`.

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
