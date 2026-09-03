# Scoop, alongside winget

Scoop is used to sideload apps that are only available from the Microsoft Store and cannot be
had through `winget`. GUI apps and official CLIs go in `windows/winget/apps.json`; anything
else goes in `scoop.json`.

## Which goes where

| Installed through | For |
|---|---|
| winget, apps.json | GUI apps, official CLIs, anything integrated with the system, anything where provenance matters |
| scoop, scoop.json | Store-only apps such as Files, portable apps, and the nonportable bucket |

## Layout

```
windows/scoop/
├── README.md
├── scoop.json   # buckets and apps, declaratively
└── apply.ps1    # installs scoop if missing, adds buckets, installs apps
```

## Running it

```powershell
# no side effects
just win-scoop -DryRun

# for real
just win-scoop
```

bootstrap.ps1 runs it as step 2.5. To skip it:

```powershell
pwsh -File windows/bootstrap.ps1 -SkipScoop
```

`apply.ps1` also takes `-SkipBuckets` and `-SkipApps`.

## The format of scoop.json

```json
{
  "buckets": ["nonportable", "extras"],
  "apps": ["files-np", "another-app"]
}
```

`buckets` are registered with `scoop bucket add`, and `apps` are installed with
`scoop install`. Scoop resolves the bucket prefix itself.

## Why avoid the Microsoft Store

- MSIX packages land in `C:\Program Files\WindowsApps\`, which belongs to TrustedInstaller, so
  configuration cannot be symlinked into them.
- Installation history is tied to a Microsoft account, which contradicts the telemetry policy
  here.
- It cannot be reproduced offline, since it requires being signed in.
- Depending on the distribution channel, an app can become paid or disappear. Files is a good
  example of the asymmetry: paid on the Store, free as an MSIX from GitHub.

The `nonportable` bucket fetches the MSIX from a GitHub release and sideloads it, which avoids
all of this.
