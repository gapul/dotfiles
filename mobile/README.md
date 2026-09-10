# Mobile: iOS and Android

Nix does not run on a phone, with Termux on Android the only exception, so phones are handled
the way `windows/` is: the declaration lives in the repository, and a machine works out how the
real device differs from it. How much of the applying can be automated depends on the platform,
and where it cannot, the tooling stops at reporting the difference.

```
mobile/
├── android/
│   ├── apps.tsv + apps.sh          # declaration against the device; F-Droid apps install too
│   ├── os-settings.conf            # global settings pushed with adb
│   ├── os-apps.tsv + os.sh         # per-app settings: permissions, battery, default launcher
│   ├── launcher-theme.py           # generates Kvaesitso's theme from palettes.json
│   └── test.sh                     # self-check against a fake adb
└── ios/
    ├── apps.tsv + sources.tsv      # App Store, AltStore Classic, AltStore PAL
    ├── apps.sh                     # declaration against the device through ideviceinstaller; cannot install
    ├── profiles/serve.sh           # serves the .mobileconfig files nix generated
    └── test.sh
nix/mobile/ios-profiles.nix         # the contents of the .mobileconfig, through pkgs.formats.plist
nix/hosts/droid.nix                 # the CLI environment inside Termux, through nix-on-droid
```

## How far the machine gets

| Layer | Android | iOS |
|---|---|---|
| Apps: declared in | `android/apps.tsv` | `ios/apps.tsv` |
| Apps: confirming they exist | `apps.sh verify`, against the F-Droid index, the GitHub API and Play | `apps.sh verify`, against the iTunes API and the AltStore source |
| Apps: comparing with the device | `apps.sh status`, over adb | `apps.sh status`, through ideviceinstaller over USB |
| Apps: installing | `apps.sh install`, F-Droid only. The rest go through Obtainium or Aurora Store | Not possible; it needs a signed ipa |
| OS settings, global | `os-settings.conf` through `os.sh` | Not possible, beyond what a `.mobileconfig` can reach |
| OS settings, per app | `os-apps.tsv` through `os.sh` | Not possible |
| Launcher | Setting the default, and generating the theme. Layout is not possible | The home screen is untouched |
| Generating profiles | — | `nix build .#ios-profiles` |
| CLI environment | `nix/hosts/droid.nix` | Not attempted. ssh to the Mac from Blink |

Everything marked as not possible has no API behind it. Standing up an MDM would let iOS be
pushed around too, but running a server and putting two devices into supervised mode is not
worth it.

`status` on both sides exits 1 if anything is MISSING, the same as
`windows/winget/status.ps1`. EXTRA, meaning something on the device that is not declared, does
not fail.

## What runs automatically and what does not

| | When it runs |
|---|---|
| Checking a declared app has not vanished from its source, `verify` | Automatically, weekly in CI, through `.github/workflows/mobile-drift.yml` |
| The scripts' own sanity, `test.sh` | Automatically, in the same CI and through `just mobile-test` |
| Comparing with the device, `status` | By hand, only when a device is plugged in |
| The `settings` part of the OS settings | Can be applied from the device itself. Once Termux has the permission, it can run from cron |
| Debloating and per-app OS settings | By hand. They need signature-level permissions, so adb only |
| Installing apps | Hand the device a file and it does the rest: Obtainium takes a URL list, Aurora Store takes Favourites |

Installing and `settings` have reached the point where handing the device a file is enough —
Obtainium's URL list, Aurora Store's favourites, and `os.sh` run from Termux. What still needs
the Mac and a cable is debloating and the per-app settings, which need signature-level
permissions, plus `status`, which counts the difference against the device.

Leaving wireless debugging permanently available over the tailnet would automate the rest, but
that would create a state where the declaration moves on while nothing is connected and it
looks applied when it is not. So those stay explicit.

What was automated instead is the opposite: the things you cannot notice at the moment they
happen. A source being renamed or deleted goes by silently, so it gets checked weekly — which
is how the rename of `Catfriend1/syncthing-android` was caught.

## Syncing app settings

Only settings that can be synced as files are synced through the home server, and the repository
holds nothing more than which app syncs through which route: the sync column in `apps.tsv` and
the table below. No keys and no databases.

| App | Route | Declared on the server in |
|---|---|---|
| Obsidian | Self-hosted LiveSync, over CouchDB | `nix/homelab/obsidian-couchdb.nix` |
| KeePassium, self-built, and KeePassDX | The kdbx through Syncthing's SyncHub | `nix/homelab/syncthing.nix` |
| Bitwarden | Vaultwarden | `nix/homelab/vaultwarden.nix` |
| ntfy | Subscribing to topics on push.gapul.net | `nix/homelab/ntfy.nix` |
| OwnTracks | Posting location to Dawarich | `nix/homelab/dawarich.nix` |
| Calendar and contacts | CalDAV and CardDAV | `nix/homelab/radicale.nix` |
| RSS | Miniflux, through the Fever API | `nix/homelab/miniflux.nix` |
| Music, video and documents | Navidrome, Jellyfin and Paperless | The respective `nix/homelab/*.nix` |
| Matrix | The homeserver at `@gapul:gapul.net` | `nix/homelab/matrix.nix` |

To add a device to Syncthing, put its device ID into `settings.devices` in
`nix/homelab/syncthing.nix` and rebuild. Committing it, rather than approving it in the web UI,
is how this repository works. The ID is a public key, so committing it is fine.

## What is deliberately not attempted

**Home screen and widget layout.** iOS offers no way at all, and Android's Kvaesitso stores it
in a binary that is not compatible between versions, so putting it in the repository would show
no meaningful diff. Only the launcher theme is declared, in `android/launcher-theme.py`.

**Backing up the apps themselves.** A full device backup is iCloud's or Seedvault's job.

**iOS settings toggles.** Nothing can touch them without supervised mode, so they are set by
hand.
