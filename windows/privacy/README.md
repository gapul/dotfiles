# Declaring Windows privacy and built-in features

The Windows equivalent of `system.defaults` in the Mac's `nix/hosts/darwin.nix`, managed
declaratively. It uses WinUtil for privacy, services, performance and features, alongside
Win11Debloat for removing the preinstalled UWP apps.

## Layout

```
windows/privacy/
├── README.md
├── winutil-config.json          # an exported ChrisTitusTech/winutil configuration
├── win11debloat-args.txt        # CLI arguments for Raphire/Win11Debloat; blank lines and `#` comments allowed
├── win11debloat-customapps.txt  # extra UWP apps to remove, beyond Win11Debloat's standard set
└── apply.ps1                    # the orchestrator that runs the three in order, plus extra registry tweaks
```

## Running it

```powershell
# see what would run, with no side effects
just win-privacy -DryRun
pwsh -File windows/privacy/apply.ps1 -DryRun

# for real. Needs administrator rights and raises a UAC prompt
just win-privacy
```

What happens:

1. Win11Debloat is fetched temporarily, through `irm https://win11debloat.raphi.re/ | iex`, and
   run automatically with the arguments in `win11debloat-args.txt`, such as `-Silent` and
   `-RunDefaults`.
2. WinUtil is fetched temporarily, through `irm https://christitus.com/win | iex`, and started
   with `winutil-config.json` passed to it. Its GUI opens, and you choose Import then Apply.

WinUtil's automatic CLI apply changes behaviour between versions, so this repository settles for
a half-automatic arrangement: the configuration is declarative, and the final Apply is a user
action.

## Changing the configuration

### Win11Debloat

Edit `win11debloat-args.txt`, one argument per line, with blank lines and `#` comments allowed.
The available arguments are at <https://github.com/Raphire/Win11Debloat#options>.

The current fifteen:

- Required: `-Silent`
- Removing UWP apps: `-RemoveApps`, `-RemoveGamingApps`
- Telemetry and AI: `-DisableTelemetry`, `-DisableBing`, `-DisableCopilot`, `-DisableRecall`
- Notifications and nudges: `-DisableLockscreenTips`, `-DisableSuggestions`,
  `-DisableStickyKeys`, `-DisableWidgets`
- Explorer: `-ShowHiddenFolders`, `-ShowKnownFileExt`, `-HideHome`, `-HideGallery`

### Arguments that turned out not to exist

These are not in Win11Debloat's wiki, so they are implemented another way:

| Intended | Instead |
|---|---|
| `-RemoveCommApps` | `microsoft.windowscommunicationsapps` in `win11debloat-customapps.txt` |
| `-RemoveDevApps` | `Microsoft.Microsoft3DViewer` and `Microsoft.MixedReality.Portal` in `win11debloat-customapps.txt` |
| `-RemoveW11Outlook` | `Microsoft.OutlookForWindows` in `win11debloat-customapps.txt` |
| `-DisableOnedrive`, which is Windows 10 only | The OneDrive uninstall step in `apply.ps1`, running `OneDriveSetup.exe /uninstall` |

### WinUtil

1. Start WinUtil on the machine: `irm https://christitus.com/win | iex`
2. Tick what you want in the GUI.
3. Save the JSON through Settings, Export Config.
4. Replace `windows/privacy/winutil-config.json` with it and commit.

## How it fits into bootstrap

`bootstrap.ps1` runs it as step 7. To skip it:

```powershell
pwsh -File windows/bootstrap.ps1 -SkipPrivacy
# or
just win-bootstrap -SkipPrivacy
```

To apply it separately afterwards:

```powershell
just win-privacy           # for real
just win-privacy -DryRun   # check the side effects
```

`apply.ps1` also takes `-SkipWinUtil`, `-SkipWin11Debloat` and `-SkipCustomApps` for partial
runs.

### Removing custom UWP apps, through win11debloat-customapps.txt

UWP apps outside Win11Debloat's standard set are removed directly with
`Get-AppxPackage | Remove-AppxPackage`. The provisioned package is removed at the same time so
they do not come back when a new user is created, which needs administrator rights.

One PackageName per line, with blank lines and `#` comments allowed.

### Extra registry tweaks

Declarative registry settings written directly in `apply.ps1`:

- `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsBackup\DisableWindowsBackupUI = 1`, which
  disables the Windows Backup UI in Windows 11 24H2. The UWP part itself belongs to CBS and
  cannot be removed, so turning the feature off is all there is.

## What this cannot cover

Registry tweaks neither tool includes go into the `$ExtraRegistry` array in `apply.ps1`, which
is the declarative extension point.

The fine-grained settings that would be `CustomUserPreferences` on macOS are handled through
each application's own policy mechanism, such as Chrome's enterprise policy.
