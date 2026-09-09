# Windows roadmap

These dotfiles grew up on macOS and WSL. This is the list of work needed to run them properly on
Windows as a native plus WSL2 hybrid, expanded from the "questions to settle on real hardware"
section of `windows/SETUP-CHECKLIST.md` into prioritised tasks.

## The machine as found, 2026-06-26

| Item | State |
|---|---|
| pwsh | Windows PowerShell 5.1 only. PowerShell 7 (`Microsoft.PowerShell`) not installed |
| winget | v1.28.240 |
| WSL | Two distros installed and stopped: `Ubuntu-24.04` and `Ubuntu` |
| CLI present | `git` via scoop, `nvim`, `yazi`, `gh`, `scoop`, `oh-my-posh` |
| CLI missing | `starship`, `zoxide`, `fzf`, `rg`, `bat`, `fd`, `jq`, `lazygit`, `sops`, `age` |
| Nerd Font | M+ family installed. `JetBrainsMono Nerd Font`, which the Terminal `fontFace` assumes, unconfirmed |

## How much of configs/ native pwsh can reuse

| Tool | Works as a symlink | Notes |
|---|---|---|
| `configs/shell/starship.toml` | Yes, unchanged | Referenced through `$env:STARSHIP_CONFIG`, already in `$PROFILE` |
| `configs/cli/gh/config.yml` | Yes | Just point `$env:GH_CONFIG_DIR` at it |
| `configs/cli/bat/` | Yes, themes only | `$env:BAT_CONFIG_DIR` |
| `configs/editors/zed/` | Yes | Zed on Windows is preview, but the config is telemetry settings only, so it is harmless |
| `configs/cli/yazi/yazi.toml` | No | `[opener]` only covers `for="macos"` and `"unix"`. Needs a Windows section |
| `configs/editors/nvim/` | No, three places | `"open"` at `obsidian.lua:36`, hardcoded XDG paths at `skkeleton.lua:10-16`, `~/Developer/...` at `lazy.lua:39` |
| `configs/terminals/tmux/` | N/A | No native Windows support; WSL only |
| `configs/terminals/ghostty/` | N/A | macOS and Linux only |

## Gaps in the WSL-Windows bridge

| Direction | State |
|---|---|
| WSL to Windows | Working: `pbcopy`/`pbpaste` through clip.exe and powershell.exe, `explorer`, a hand-written `wslview`, a `code` wrapper |
| Windows to WSL | Only the `wsl-here` function. Sharing the SSH agent, 1Password, GPG and the git credential helper is unhandled |

---

## Tasks by priority

### P0, needed to work at all

| # | Task | State |
|---|---|---|
| P0-1 | Install `Microsoft.PowerShell` (7) through winget at the top of `bootstrap.ps1`. PSReadLine's `PredictionSource` fails on the version bundled with 5.1, so the profile detects capabilities and supports both | Done, 38efee9; the PSReadLine detection landed with P1-8 |
| P0-2 | Add a `Find-DotfilesToolOverlap` helper to profile.ps1 to diagnose scoop/winget overlap, and write the "winget first, scoop as backup" policy into the README | Done, 4cdc178 |
| P0-3 | Add `verify.ps1` to check mechanically that every ID in `apps.json` exists | Done, 38efee9 |
| P0-4 | Automate the Nerd Font: add `DEVCOM.JetBrainsMonoNerdFont` to `apps.json` | Done, 38efee9 |

IDs that were uncertain, resolved against the real machine:

| Guess | Correct winget ID |
|---|---|
| sops | `SecretsOPerationS.SOPS` (3.12.2). Mozilla.SOPS is the old one |
| gitleaks | `Gitleaks.Gitleaks` (8.30.1) |
| typst | `Typst.Typst` |
| bottom | `Clement.bottom` (0.14.1) |
| mpv | `shinchiro.mpv` (0.41.0) |
| jetbrains nerd font | `DEVCOM.JetBrainsMonoNerdFont` (3.3.0) |

### P1, a complete native experience

| # | Task | State |
|---|---|---|
| P1-5 | Add `New-DotfilesLink` to `bootstrap.ps1`, symlink `gh`, `bat`, `yazi`, `nvim` and `zed`, place `$PROFILE` for both pwsh 7 and 5.1, and support `-DryRun` | Done, 5d1f218 |
| P1-6 | Add a `for = "windows"` `[opener]` section to `configs/cli/yazi/yazi.toml`: `start "" "$@"`, `tar -xf`, `nvim`, `mpv` | Done, d9485d4 |
| P1-7 | Branch the three nvim spots on `vim.fn.has("win32")`: obsidian.lua's follow_url, skkeleton.lua's dictionary path, lazy.lua's dev.fallback | Done, 26e0aa7 |
| P1-8 | Native SOPS decryption: set `$env:SOPS_AGE_KEY_FILE` and add `Get-DotfilesSecret` and `Copy-DotfilesSecret` | Done |

### P2, operational quality

| # | Task | State |
|---|---|---|
| P2-9 | Add `win-bootstrap`, `win-verify` and `win-fmt` (PSScriptAnalyzer) to the Justfile, and `Casey.Just` to apps.json | Done, d7156c1 |
| P2-10 | Add a windows-latest job to `check.yml` doing parse, `-DryRun` and PSScriptAnalyzer, and keep the BOM through `.gitattributes` | Done, 34640ca, green in real CI |
| P2-11 | Auto-start the Windows ssh-agent service from bootstrap and share it into WSL over `npiperelay` and `socat` | Done, 15de024 |
| P2-12 | Document the scoop/winget policy in the README, folded into P0-2 | Done, 4cdc178 |

### P3, polishing the hybrid

| # | Task | State |
|---|---|---|
| P3-13 | Windows Terminal `settings.json`: default profile becomes pwsh 7, Windows PowerShell 5.1 stays visible, Ubuntu (WSL) is kept | Done |
| P3-14 | Share espanso through `Espanso.Espanso` in apps.json plus a match/base.yml symlink. SKK needs the Windows-only `nathancorvussolis.corvusskk`, since the macOS plist cannot be ported | Done |
| P3-15 | Add a Windows section to `docs/CHEATSHEET.md`: the mapping from macOS commands, the native pwsh functions, and a note on the per-OS SKK implementations | Done, 0c3197b |

### P4, more polish

| # | Task | State |
|---|---|---|
| P4-16 | Add `Open-Wsl`, `ConvertTo-WslPath` and `ConvertFrom-WslPath` to profile.ps1 | Done |
| P4-17 | Set `$env:GHQ_ROOT` to `%USERPROFILE%\Developer` so it agrees with nvim's lazy.lua dev.path, and add `x-motemen.ghq` to apps.json | Done |
| P4-18 | Add `win-upgrade` and `win-status` to the Justfile, with `status.ps1` diffing the declaration against what is installed | Done |
| P4-19 | Move `$PSScriptRoot` in verify.ps1 and status.ps1 out of the param default expression and into the body, where it is not empty under 5.1 | Done, 5b00bf7 |

### P5, self-diagnosis

| # | Task | State |
|---|---|---|
| P5-20 | Add `Test-DotfilesSetup` to profile.ps1, the equivalent of `just doctor` on macOS. Five sections: config symlinks, environment variables, the main tools, key ACLs, and the ssh-agent service | Done |
| P5-21 | Set `STARSHIP_CONFIG` unconditionally rather than behind `Get-Command starship`, so the variable is right even before the tool is installed | Done, 01449f3 |

### P6, the real setup run

| # | Task | State |
|---|---|---|
| P6-22 | Run `bootstrap.ps1` for real on the machine, through the UAC prompt. Started 20:30:57, finished 21:12:08, 41 minutes. 36 apps installed through winget import, all six symlinks created, ssh-agent service Auto and Running, git config overwritten | Done |
| P6-23 | `Test-DotfilesSetup` reports 17 of 17 passing: six symlinks, three environment variables, five tools, one key, one service, and the STARSHIP_CONFIG/SOPS/GHQ acknowledgements. starship, zoxide, sops and age show as missing only because the current process PATH is stale; winget list has them, and a new terminal resolves it | Done |
| P6-24 | Clean up GUI apps that turned out to be unwanted: removed `Microsoft.VisualStudioCode` and `Brave.Brave` from apps.json and uninstalled them. Added `Anthropic.ClaudeCode`, already present, and `KeePassXCTeam.KeePassXC` as the minimum replacements | Done |
| P6-25 | KeePassXC failed to install on its own with MSI 1618, another installation in progress: the msiexec started during bootstrap was still holding the session with administrator rights. It stays in apps.json, so the next bootstrap or `winget install KeePassXCTeam.KeePassXC --exact` after a reboot will get it | Pending, after a reboot |
| P6-26 | Clone `~/.dotfiles` in WSL Ubuntu-24.04 and run `bootstrap-wsl.sh`. Step 1 (apt) and step 2 (Nix 2.34.7) skipped as already satisfied; step 4 stopped on the missing age key. SSH agent sharing proven temporarily through `nix shell nixpkgs#socat`: socat to npiperelay to `//./pipe/openssh-ssh-agent`, with `ssh-add -L` answering "The agent has no identities", which is the connection working and simply having no keys | Done |
| P6-27 | Add logic to the wsl.nix zsh init that builds the npiperelay PATH from `WIN_USER` through WinGet Packages, verified on the machine: `WIN_USER=ispc_5CG54406V7`, `npr_dir=...albertony.npiperelay_...`, npiperelay.exe present | Done, fb0b11e |

### P7, WezTerm in place of Ghostty

| # | Task | State |
|---|---|---|
| P7-28 | Ghostty is macOS and Linux only and will not start on native Windows, so WezTerm takes its place as the cross-platform terminal. Added `configs/terminals/wezterm/wezterm.lua`, translating the Ghostty config into Lua: HackGen Console NF, Rose Pine, opacity 0.88, blur 30, no close confirmation, Ctrl+C as SIGINT. The OS branch gives Mac `macos_window_background_blur` and Windows `win32_system_backdrop = 'Acrylic'` | Done |
| P7-29 | Add `wez.wezterm` to apps.json, add wezterm to `bootstrap.ps1`'s ConfigLinks as a single-file symlink to `%USERPROFILE%\.wezterm.lua`, and add it as the seventh entry in `Test-DotfilesSetup`'s symlink check | Done, 1b4314e |
| P7-30 | Review the 30 EXTRA entries `status.ps1 -ShowExtra` found on the machine. Sixteen were installed deliberately and went into apps.json (WSL, Terminal, WM, launcher, browser, sync, utilities, games); system-dependent, OEM and version-fragment entries stay undeclared. INSTALLED went from 42/45 to 58/61 and EXTRA from 30 to 14 | Done, ac85464 |

### P8, declaring telemetry and built-in features

The Windows equivalent of `system.defaults` in the Mac's `nix/hosts/darwin.nix`.

| # | Task | State |
|---|---|---|
| P8-31 | Add `windows/privacy/`: `win11debloat-args.txt` with 13 CLI arguments for `Raphire/Win11Debloat` (Silent, RemoveApps, DisableTelemetry, DisableBing, DisableCopilot, DisableRecall, DisableLockscreenTips, DisableSuggestions, DisableSticky, ShowHiddenFolders as the `AppleShowAllFiles` equivalent, ShowKnownFileExt as `AppleShowAllExtensions`, HideHome, HideGallery), and `winutil-config.json` in `ChrisTitusTech/winutil`'s export format with 13 tweaks | Done |
| P8-32 | Add the `windows/privacy/apply.ps1` orchestrator: Win11Debloat runs from the CLI automatically, WinUtil starts its GUI and imports the config. Supports `-DryRun`, `-SkipWinUtil` and `-SkipWin11Debloat`. `-Encoding UTF8` is passed explicitly because PowerShell 5.1's `Get-Content` defaults to ANSI | Done |
| P8-33 | Add `win-privacy *flags` to the Justfile and run it as step 7 of `bootstrap.ps1`, skippable with `-SkipPrivacy`. `apply.ps1` keeps its own `-SkipWinUtil` and `-SkipWin11Debloat` so the choice stays fine-grained | Done |

### P9, replacing the Microsoft defaults, and scoop

Replacing the built-in apps (File Explorer, OneDrive, Mail, Defender, Photos, Paint, Voice
Recorder and so on) with things that line up with the Mac's `brew cask` set.

| # | Task | State |
|---|---|---|
| P9-34 | Add 12 GUI apps to `apps.json`: `Syncthing.Syncthing` for OneDrive, `Mozilla.Thunderbird` for Mail, `WinSCP.WinSCP` for Cyberduck, `ente-io.auth-desktop` for 2FA, `WiresharkFoundation.Wireshark`, `KDE.Krita` for Paint, `Ditto.Ditto` for Maccy-style clipboard history, `Captura.Captura` for screen recording, `Bitdefender.Bitdefender` in place of Defender, `Henry++.simplewall` as the LuLu-equivalent outbound firewall, `Microsoft.Sysinternals.Autoruns` for persistence monitoring like BlockBlock and KnockKnock, and `Malwarebytes.Malwarebytes` as a second opinion scanner | Done |
| P9-35 | Integrate scoop for sideloading Store-only apps such as Files. Add `windows/scoop/` with a declarative `scoop.json` of buckets and apps plus an `apply.ps1` orchestrator that installs scoop, adds buckets and installs apps, supporting `-DryRun`, `-SkipBuckets` and `-SkipApps`. Runs as step 2.5 of `bootstrap.ps1`, skippable with `-SkipScoop`, with `win-scoop *flags` in the Justfile. The File Explorer replacement sideloads through `nonportable/files-np`, avoiding the Store | Done |
| P9-36 | Add six arguments to `win11debloat-args.txt`: `-RemoveCommApps` (Mail, Calendar, People, now that Thunderbird is in), `-RemoveDevApps` (3D Builder, MR Portal), `-RemoveW11Outlook` (the forced new Outlook), `-RemoveGamingApps` (all Xbox, since Steam is what gets used), `-DisableOnedrive` (replaced by Syncthing) and `-DisableWidgets` (taskbar weather and news) | Done |
| P9-37 | Voice recording and photo preview: on hold, since neither use is settled. The recorder is for meetings and a suitable open-source option is still being looked for; the photo viewer candidates are still being narrowed | Pending |
| P9-38 | Remove custom UWP apps: add `win11debloat-customapps.txt` with the eight outside Win11Debloat's standard set (`Microsoft.GetHelp`, `Microsoft.Windows.DevHome`, `Microsoft.YourPhone`, `Microsoft.OfficePushNotificationUtility`, `Microsoft.CommandPalette`, `AppUp.IntelGraphicsExperience`, `aimgr`, `Microsoft.MicrosoftStickyNotes`), and add step 1.5 to `apply.ps1` doing `Get-AppxPackage \| Remove-AppxPackage` plus provisioned package removal, skippable with `-SkipCustomApps`. The riskier three (`Microsoft.BingSearch`, `Microsoft.Windows.ContentDeliveryManager`, `Microsoft.StartExperiencesApp`) are excluded and handled by turning the feature off instead | Done |
| P9-39 | Turn off Windows Backup. The UWP part cannot be removed because it belongs to `MicrosoftWindows.Client.CBS`, so step 1.7 of `apply.ps1` sets `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsBackup\DisableWindowsBackupUI = 1` declaratively | Done |
| P9-40 | Remove `Typst.Typst` from apps.json, unused for now and easy to add back | Done |
| P9-41 | Machine cleanup, in a separate commit and not affecting apps.json: HP's preinstalled Bitdefender Total Security trio (VPN uninstalled, Total Security itself already absent, BDContextualMenu removed through Remove-AppxPackage); Poly.PolyLens removed along with the Poly Lens Control Service MSI; leftover Start menu shortcuts (OneNote.lnk, the Office language settings link) deleted; the desktop Office 2013 turned out never to have been installed, leaving only preinstall UI remnants. The HP Wolf Security family (Wolf, Sure Run, Sure Recover, One Agent, Security Update) and Vivado are protected | Done |
| P9-42 | Four fixes to how Win11Debloat is invoked: (a) the short URL `win11debloat.raphi.re` redirects to a GitHub user page, so the release asset's `Get.ps1` launcher is fetched directly; (b) `(Invoke-WebRequest).Content` returns a byte[] under PowerShell 7, so `-OutFile` writes the binary directly; (c) in-process splatting collides with `[CmdletBinding(SupportsShouldProcess)]` when binding switch arguments, so it runs `-File` in a separate pwsh process; (d) fetching `Win11Debloat.ps1` alone fails with "unable to find required files" because of the multi-file layout, so the Get.ps1 launcher, which pulls the whole repo, is used instead | Done |
| P9-43 | Automatic UAC elevation for the apply scripts: `windows/privacy/apply.ps1` and `windows/sharpkeys/apply.ps1` started without administrator rights raise a UAC prompt through `Start-Process pwsh -Verb RunAs` and re-run in the child process with the original switches. `-DryRun` needs no elevation and skips it | Done |

#### Where each Microsoft default ended up

| Category | Microsoft | Replacement |
|---|---|---|
| Terminal | Windows Terminal | WezTerm |
| Shell | PowerShell 5.1 | PowerShell 7 |
| Editor | Notepad | Neovim |
| Browser | Edge | Chrome, Zen Browser |
| Launcher | Start search | Flow Launcher and Everything |
| Screenshots | Snipping Tool | ShareX |
| Window manager | Snap | GlazeWM |
| Key mapping | none | SharpKeys, AutoHotkey, PowerToys |
| Phone | Phone Link | KDE Connect and LocalSend |
| Photo viewer | Photos | undecided |
| Mail and calendar | Mail, Outlook | Thunderbird |
| Notes | Sticky Notes | Obsidian |
| File sync | OneDrive | Syncthing |
| Clipboard history | Win+V, volatile | Ditto, persisted in SQLite |
| Painting | Paint | Krita |
| Screen recording | Game Bar | Captura, with OBS and ShareX |
| 2FA | none | Ente Auth |
| Antivirus | Defender | Bitdefender Free; Defender switches itself to passive |
| Outbound firewall | Defender Firewall | simplewall, the LuLu equivalent |
| Persistence monitoring | none | Sysinternals Autoruns, standing in for BlockBlock and KnockKnock |
| Second-opinion scanner | none | Malwarebytes Free |
| File manager | File Explorer | Files, through the scoop nonportable bucket, avoiding the Store |
| Privacy and telemetry | on by default | disabled declaratively through Win11Debloat and WinUtil |

### P10, declaring the keymap, the Karabiner equivalent

Reproducing the Mac's Karabiner-Elements remapping on Windows. Two layers reach the same
expressiveness: single physical keys go through the SharpKeys mechanism, a Scancode Map registry
value, and combinations go through AutoHotkey.

| # | Task | State |
|---|---|---|
| P10-42 | Add `windows/sharpkeys/`: `keymap.skl` in SharpKeys' human-readable format, an `apply.ps1` that writes `HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout\Scancode Map` as binary directly in PowerShell without needing the SharpKeys GUI, and a README. CapsLock (0x3A) becomes Left Ctrl (0x1D), declaratively. Supports `-DryRun` and `-Clear`, which removes everything and returns to standard | Done |
| P10-43 | Add `windows/autohotkey/` with `keymap.ahk` in AHK v2, doing two things. First, the Copilot key becomes Right Ctrl, as insurance for OEM machines where SharpKeys cannot remap that scancode alone; the candidates `F23`, `+#F23`, `vk89` and `sc15D` are left in comments and were checked with KeyHistory on the machine. Second, the Emacs shortcuts come back: `Ctrl+A` to Home, `Ctrl+E` to End, `Ctrl+B` to Left, `Ctrl+F` to Right, `Ctrl+P` to Up, `Ctrl+N` to Down, `Ctrl+H` to Backspace, `Ctrl+D` to Delete, `Ctrl+K` to Shift+End then Delete. Terminals (`ConsoleWindowClass`, `CASCADIA_HOSTING_WINDOW_CLASS`, WezTerm, mintty) and editors (Vim, VS Code, Cursor, nvim) are excluded through `#HotIf !IsEmacsExcluded()` | Done |
| P10-44 | Add step 8 to `bootstrap.ps1`: call the SharpKeys apply.ps1 and symlink the AHK script to `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\dotfiles-keymap.ahk` so it starts at login. Skippable with `-SkipKeymap`. Add `win-keymap *flags` to the Justfile, which applies SharpKeys and reloads AHK | Done |

### P11, declaring the locale: SKK alone, UTF-8, US region

Running an English UI while getting rid of the Shift-JIS mojibake, where `\` shows as `¥`, and
the redundant IMEs.

| # | Task | State |
|---|---|---|
| P11-45 | `windows/locale/apply.ps1` applies three things declaratively. (A) The user language list becomes `ja-JP` alone with `InputMethodTips` set to CorvusSKK's fixed CLSID (`{EAEA0E29-AA1E-48EF-B2DF-46F4E24C6265}{956F14B3-5310-4CEF-9651-26710EB72F3A}`), and `Set-WinUILanguageOverride en-US` fixes the UI to English. This removes the English keyboard layout (`0409:00000409`) and MS-IME, and with them the Win+Space switch. (B) `Set-WinSystemLocale en-US` plus setting `ACP`, `OEMCP` and `MACCP` under `HKLM\...\Nls\CodePage` from 932 to 65001, the Beta UTF-8 feature, which is what actually fixes `\` showing as `¥`. (C) `Set-WinHomeLocation -GeoId 244` for the US. It elevates itself through UAC and supports `-DryRun` and `-Skip{LanguageList,SystemLocale,HomeLocation}` | Done |
| P11-46 | Wire it in as step 9 of `bootstrap.ps1`, skippable with `-SkipLocale`, and add `win-locale *flags` to the Justfile | Done |

### P12, declaring the window manager: AeroSpace to GlazeWM, Karabiner to AHK

Porting the Mac's AeroSpace tiling window manager and Karabiner's app shortcuts to Windows.

| # | Task | State |
|---|---|---|
| P12-47 | `configs/wm/glazewm/config.yaml` translates AeroSpace's Hyper key (`cmd+ctrl+alt`) one-to-one to Win+Ctrl+Alt, covering focus, move, resize, workspace switching 1-9 and 0, move-to-workspace, floating, fullscreen, the resize binding mode, monitor switching, workspace back-and-forth, the launcher (Flow Launcher) and the terminal (WezTerm). The same muscle memory drives both window managers | Done |
| P12-48 | Port Karabiner's `cmd-ctrl-alt-o` to Obsidian as `#^!o::Run "obsidian://"` in `windows/autohotkey/keymap.ahk`, with `#^!Enter::Run "wezterm-gui.exe"` as a fallback | Done |
| P12-49 | `configs/wm/zebar/{styles.css, settings.json}` aims to match SketchyBar on the Mac: the Tokyo Night palette becomes Rose Pine, matching `atuin`, `bat`, `man`, `wezterm` and sketchybar; SketchyBar-style widget pills; a faint `box-shadow`; inverted colours on the focused workspace; Love for high CPU and Foam while charging. The `<i>` icons use HackGen Console NF first, whose Nerd build has the glyphs, falling back to M+Code and JetBrainsMono Nerd Font | Done |
| P12-50 | Add `glazewm`, `zebar-css` and `zebar-settings` to `bootstrap.ps1`'s ConfigLinks, symlinked to `~/.glzr/glazewm/config.yaml` and `~/.glzr/zebar/{styles.css,settings.json}` | Done |
| P12-51 | Fork Zebar's `bar.html` and add `sketchybar-app-font` with `icon_map.sh` converted to JSON, to make the focused app icon as precise as SketchyBar's | Pending |

### P13, declaring fonts, user-scope installs for sketchybar-app-font and others

The same idea as installing `font-*` casks through home-manager on the Mac.

| # | Task | State |
|---|---|---|
| P13-52 | `windows/fonts/apply.ps1` copies `configs/fonts/*.ttf` and `*.otf` into `%LOCALAPPDATA%\Microsoft\Windows\Fonts\` and registers them under `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts`, using the user-scope font install available since Windows 10 1809, which needs no administrator rights. Idempotent, skipping when the file and registry value already match, with `-DryRun` and `-Force` | Done |
| P13-53 | Wire it in as step 8.5 of `bootstrap.ps1`, skippable with `-SkipFonts`, and add `win-fonts *flags` to the Justfile | Done |

### P14, Bitwarden Desktop's SSH agent plus WSL forwarding

Using the SSH agent feature of Bitwarden Desktop 2025.1.2 and later on the lab PC. The Windows
OpenSSH ssh-agent service is disabled so Bitwarden owns `\\.\pipe\openssh-ssh-agent`, and WSL
forwards transparently through socat and npiperelay.

| # | Task | State |
|---|---|---|
| P14-54 | Add `Bitwarden.Bitwarden`, the desktop GUI, to apps.json; Bitwarden.CLI was already there. The private and public keys go into the vault as an SSH Key item, and the agent is enabled under Settings, SSH Agent, followed by a Bitwarden restart | Done |
| P14-55 | Add a `-UseBitwardenSSH` flag to `bootstrap.ps1`. When given it runs `Stop-Service ssh-agent` and `Set-Service ssh-agent -StartupType Disabled`, because Windows OpenSSH and Bitwarden compete for the same pipe name. Without it, the service stays Auto and Running as before | Done |
| P14-56 | On the WSL side the existing socat and npiperelay forwarding in `nix/home/wsl.nix` connects to Bitwarden's pipe unchanged, since the socket name is the same `\\.\pipe\openssh-ssh-agent`. `ssh-add -l` shows the Bitwarden keys | Done, verified on the machine |
| P14-57 | The Bitwarden approval prompt on first SSH use goes away once `npiperelay.exe` is added under Settings, SSH Agent, Auto-approve or the whitelist | Pending, a GUI action for the user |

### P15, the asymmetric username on the lab PC, and keeping personal details out of git

The Mac is `yuki`; the lab PC is `ispc_5cg54406v7`, which is company-assigned and cannot be
changed. This handles that without leaving personal details in a public repository and without
breaking `yuki` on the Mac.

| # | Task | State |
|---|---|---|
| P15-58 | Add a generically named `homeConfigurations.labpc-wsl` to `nix/flake.nix`. If `./user.local.nix` exists it overrides through `user // import ./user.local.nix`; otherwise `user` is used unchanged | Done |
| P15-59 | Commit `nix/user.local.nix.example` as a template and add `nix/user.local.nix` to `.gitignore`, keeping personal details local | Done |
| P15-60 | Move `xcodegen` from `nix/home/common.nix` to `nix/home/darwin.nix`, so a home-manager apply on Linux or WSL does not hit `Refusing to evaluate package 'xcodegen' ... meta.platforms = [ darwin ]` | Done |
| P15-61 | The WSL home-manager apply: `nix run github:nix-community/home-manager -- switch --flake ~/.dotfiles/nix#labpc-wsl`, and `nix flake update --flake ./nix`, since the bare name collides with the registry | In progress on the machine |

---

## Order

```
P0-1 → P0-3 → P0-4 → P0-2      bootstrap runs reliably
       ↓
P1-5 → P1-6 → P1-7 → P1-8      configs are actually read natively
       ↓
P2-9 → P2-10 → P2-11 → P2-12   turn the practices into rules
       ↓
P3-13 → P3-14 → P3-15          polish
```
