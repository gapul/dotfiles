# Declaring Windows privacy and built-in features

The Windows equivalent of `system.defaults` in the Mac's `nix/hosts/darwin.nix`, managed
declaratively. Two upstream tools do the broad work — Win11Debloat for preinstalled UWP apps and
most privacy switches, WinUtil for services and a few tweaks — and a baseline of our own covers
the telemetry settings that must hold whatever those tools do in a given release.

## Layout

```
windows/privacy/
├── README.md
├── apply.ps1                    # the orchestrator: runs everything below in order
├── verify.ps1                   # read-only check of the machine against baseline.psd1
├── baseline.psd1                # registry values, services and scheduled tasks we set ourselves
├── upstream.psd1                # the pinned Win11Debloat and WinUtil: version, URL, SHA256
├── check-upstream.sh            # checks the declarations against the pinned upstream (macOS/Linux, CI)
├── update-upstream.sh           # re-pins upstream.psd1 to the latest releases
├── win11debloat-args.txt        # CLI arguments for Raphire/Win11Debloat; blank lines and `#` comments allowed
├── win11debloat-customapps.txt  # extra UWP apps to remove, beyond Win11Debloat's standard set
└── winutil-config.json          # the WinUtil tweak IDs to apply, as a flat JSON array
```

## Running it

From an administrator PowerShell, 5.1 or 7:

```powershell
just win-privacy -DryRun   # see what would run, with no side effects
just win-privacy           # for real; raises a UAC prompt if not elevated
just win-privacy-verify    # afterwards, and after Windows updates: exits 1 on drift
```

`apply.ps1` runs, in order:

1. **Win11Debloat**, the pinned commit's source zip, with the arguments in
   `win11debloat-args.txt`. Fully unattended.
2. **Custom UWP removal** of the apps in `win11debloat-customapps.txt`, for the current user and
   the provisioned package, so a new account does not get them back.
3. **OneDrive uninstall** through `OneDriveSetup.exe /uninstall`.
4. **WinUtil**, the pinned release, run headless with `-Config winutil-config.json`. WinUtil
   applies the selection and exits without opening its window. Release 26.10.07 exits 1 even
   when every tweak applied, because its telemetry tweak tries to disable a `wermgr` service
   that does not exist, so a non-zero WinUtil exit is reported as a warning; the `[ERROR]`
   lines in the output say which tweak.
5. **Baseline**, everything in `baseline.psd1`: policy registry values, services stopped and
   disabled, scheduled tasks disabled. It runs last so that our values win where a tool touches
   the same key.

Partial runs: `-SkipWin11Debloat` (steps 1 and 3), `-SkipCustomApps`, `-SkipWinUtil`,
`-SkipBaseline`.

Any failure is printed in red and counted; the run ends with `失敗 N 件` and exits 1. When
`apply.ps1` relaunches itself elevated it waits for the elevated run and passes its exit code
on, so `just win-privacy` and `bootstrap.ps1` see it. The elevated window closes when it
finishes, so the whole output is also written to
`%LOCALAPPDATA%\dotfiles\privacy-apply-<timestamp>.log`. `bootstrap.ps1` runs all of it as step 7 unless given `-SkipPrivacy`.

## Pinned upstream

Both tools are downloaded at run time, but never "whatever is latest": `upstream.psd1` names the
exact Win11Debloat commit and WinUtil release, and `apply.ps1` refuses to run either one unless
the download matches the SHA256 recorded there. So a run applies what was reviewed, and a
compromised or changed upstream fails closed instead of running as administrator.

The downloads go to a fresh directory under `%SystemRoot%\Temp` that only Administrators and
SYSTEM can write, with that ACL set as the directory is created. `%TEMP%` would not do: the
unelevated user can write there, and could swap the file between the hash check and its
execution.

The Win11Debloat pin is a GitHub source archive, which GitHub generates on request. GitHub has
changed archive bytes once before (January 2023, reverted). If that happens again the hash check
fails and nothing runs; re-pin with `update-upstream.sh` after checking the upstream commit is
unchanged.

Win11Debloat's own launcher (`Get.ps1`) is not used, because it fetches the latest source
itself; `apply.ps1` extracts the pinned zip and calls `Win11Debloat.ps1` directly with Windows
PowerShell 5.1, as the launcher would.

To move to newer versions, on macOS or Linux:

```sh
just win-privacy-update-upstream   # rewrites upstream.psd1, then runs the check below
just win-privacy-check-upstream    # also runs in CI (.github/workflows/windows.yml)
```

`check-upstream.sh` downloads the pinned files, checks their hashes, and checks that every
argument in `win11debloat-args.txt` is a parameter of that `Win11Debloat.ps1` and every ID in
`winutil-config.json` exists in that `winutil.ps1`. This matters: a headless WinUtil run applies
nothing if one ID is unknown, and WinUtil renames IDs between releases. Before October 2026 the
config used a format and nine IDs (`WPFTweaksTele`, `WPFTweaksAH`, `WPFTweaksRP` and others)
that the current WinUtil no longer accepts, so it could not be applied as written.

## The baseline

`baseline.psd1` is the single source for both `apply.ps1` and `verify.ps1`. It holds what was
confirmed on a Windows 11 Pro install (build 26300, in a VM) to stop the telemetry pipeline:

- Registry: the `DataCollection` policies, application compatibility telemetry and CEIP, Windows
  Error Reporting, tailored experiences and consumer features, Copilot and Recall, the
  advertising ID, web results in search, and publishing or uploading activity history.
  `EnableActivityFeed` is left to WinUtil, whose `WPFTweaksActivity` sets it to 1 to keep
  clipboard history working.
- Services: `DiagTrack`, `dmwappushservice` and `WerSvc`, stopped and disabled.
- Scheduled tasks: Application Experience, CEIP, disk diagnostics, feedback, error reporting and
  usage data reporting. A task the build does not have is skipped.

On Home and Pro, `AllowTelemetry = 0` is treated as 1, "Required"; only Enterprise and
Education honour 0. What actually stops the uploads there is `DiagTrack` being disabled.
Windows Update, Defender, Edge and the Store still talk to Microsoft on their own; only cutting
the network stops those.

Windows can put some of this back; a feature update can restore a service. `PcaPatchDbTask` is
deliberately not in the list: it only patches the compatibility database, and Windows re-enables
it at every boot, so it would always show as drift. `verify.ps1` is how you find out; re-apply
only the baseline with `just win-privacy -SkipWin11Debloat -SkipCustomApps -SkipWinUtil`.

## Changing the configuration

### Win11Debloat

Edit `win11debloat-args.txt`, one argument per line. The available arguments are at
<https://github.com/Raphire/Win11Debloat#options>, and `check-upstream.sh` checks them against
the pinned version.

The current fifteen:

- Required: `-Silent`
- Removing UWP apps: `-RemoveApps`, `-RemoveGamingApps`
- Telemetry and AI: `-DisableTelemetry`, `-DisableBing`, `-DisableCopilot`, `-DisableRecall`
- Notifications and nudges: `-DisableLockscreenTips`, `-DisableSuggestions`,
  `-DisableStickyKeys`, `-DisableWidgets`
- Explorer: `-ShowHiddenFolders`, `-ShowKnownFileExt`, `-HideHome`, `-HideGallery`

These were once intended but are not Win11Debloat arguments, so they are done another way:

| Intended | Instead |
|---|---|
| `-RemoveCommApps` | `microsoft.windowscommunicationsapps` in `win11debloat-customapps.txt` |
| `-RemoveDevApps` | `Microsoft.Microsoft3DViewer` and `Microsoft.MixedReality.Portal` in `win11debloat-customapps.txt` |
| `-RemoveW11Outlook` | `Microsoft.OutlookForWindows` in `win11debloat-customapps.txt` |
| `-DisableOnedrive`, which is Windows 10 only | The OneDrive uninstall step in `apply.ps1` |

### WinUtil

`winutil-config.json` is a flat JSON array of IDs, the format WinUtil's own Export writes. The
current nine:

| ID | What it does |
|---|---|
| `WPFTweaksTelemetry` | Disables Microsoft telemetry |
| `WPFTweaksActivity` | Disables activity history |
| `WPFTweaksLocation` | Disables location tracking |
| `WPFTweaksRemoveHomeAndGallery` | Removes Home and Gallery from Explorer, opens This PC |
| `WPFTweaksEndTaskOnTaskbar` | Adds End Task to the taskbar's right-click menu |
| `WPFTweaksRightClickMenu` | Restores the classic context menu |
| `WPFTweaksRestorePoint` | Creates a restore point first |
| `WPFTweaksServices` | Sets a list of services to Manual |
| `WPFTweaksStorage` | Disables Storage Sense |

What the old IDs did that has no current equivalent is covered elsewhere: Bing search and
Copilot by Win11Debloat's `-DisableBing` and `-DisableCopilot`. `WPFTweaksWifi` and
`WPFTweaksDisableLMS1` were removed upstream and are gone.

To pick tweaks in the GUI instead: run the pinned `winutil.ps1`, select, Export, and replace the
file with the export. Then run `check-upstream.sh`.

### Custom UWP apps

`win11debloat-customapps.txt`, one PackageName per line, blank lines and `#` comments allowed.

### Baseline

Add entries to `baseline.psd1`. Registry values are DWords. `HKCU` entries go to the account
the elevated `apply.ps1` runs as. That is you when your own account is an administrator; if you
elevate with a different administrator's credentials, they land in that account's hive and
`verify.ps1` run as you reports them as drift.

## What this cannot cover

Fine-grained per-application settings, the `CustomUserPreferences` of macOS, go through each
application's own policy mechanism, such as Chrome's enterprise policy.
