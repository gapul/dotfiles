# dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Declarative macOS configuration built on a Nix flake: nix-darwin, home-manager, sops-nix.

Day-to-day commands live in [docs/CHEATSHEET.md](docs/CHEATSHEET.md).

---

## Forking this

```bash
# 1. Fork, then clone under your own name
git clone git@github.com:<yourname>/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# 2. Edit nix/user.nix. Every nix module reads from here.
$EDITOR nix/user.nix
# {
#   username     = "<your-macos-username>";
#   gitUser      = "<your-github-username>";
#   gitEmail     = "<your-email>";
#   dotfilesRepo = "https://github.com/<yourname>/dotfiles.git";
# }

# 3. Generate an age key and replace the public key in .sops.yaml
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# Copy the "# public key: age1..." line into .sops.yaml
$EDITOR .sops.yaml

# 4. The previous owner's secrets cannot be decrypted, so start empty
rm secrets/secrets.yaml
sops secrets/secrets.yaml   # opens an editor; write your own secrets as YAML

# 5. Optional: drop the personal brew taps
$EDITOR nix/hosts/darwin.nix
# "gapul/openutau" and "gapul/zrythm" are personal forks and can go.
# GUI casks you do not want (gimp, blender, ...) can go too.

# 6. Bootstrap
bash scripts/bootstrap.sh
```

After cloning, `nix/user.nix`, `.sops.yaml` and `nix/hosts/darwin.nix` are the only files
you need to touch. Everything else works unchanged.

## Layout

```
nix/
|-- flake.nix        entry point: darwin / nixos / home-manager configurations and devShells
|-- user.nix         username, email and so on. Edit this first.
|-- hosts/           per machine: darwin.nix (main Mac), macmini.nix, nixos-laptop.nix, wsl.nix
|-- home/            home-manager: common.nix plus per-OS (darwin/linux/wsl/hyprland) and backup
|-- lib/             theming. palettes.json is the single source for rose-pine dark and light.
`-- pkgs/            packages built here rather than taken from nixpkgs
configs/             real application configs (ghostty, tmux, sketchybar, nvim, karabiner, yazi, ...)
secrets/secrets.yaml age-encrypted through SOPS
.sops.yaml           recipients (age public keys)
scripts/bootstrap.sh zero-to-one setup for a new Mac. Linux and WSL variants live alongside it.
windows/             Windows-side setup (winget, scoop, AutoHotkey, ...)
mobile/              iOS and Android: app declarations, adb settings, configuration profiles
esphome/             device configs that run on ESP chips (the plant waterer)
tailscale/           tailnet policy: ACLs and split DNS. Fetched, not committed by hand.
nextdns/             NextDNS profile settings. Fetched, not committed by hand.
templates/           direnv dev-shell templates (node, python, rust)
Justfile             the commands used day to day
```

## Getting started

On a new Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/gapul/dotfiles/main/scripts/bootstrap.sh | bash
```

## Commands

### Justfile recipes

Generated from `just --list`. Run `just docs` after changing a recipe.

<!-- BEGIN just-list -->
```text
    default

    [Backup]
    archive path                                      # Example: `just archive ~/Downloads/old-project`
    archive-find pattern                              # Example: `just archive-find "*.psd"` / `just archive-find old-project`
    archive-ls                                        # List archive (--tag archive) snapshots (ID / date / original path)
    archive-stats                                     # Total size and file count of the archive
    backup                                            # Run the warm backup now (kickstart launchd) -> follow the log (Ctrl-C ends following; backup continues)
    backup-check                                      # Verify repository integrity (restic check)
    backup-ls                                         # List all snapshots (distinguish warm / archive by the Tags column)
    gdrive cmd="status"                               # ~/Library/LaunchAgents/com.gapul.rclone.* plists are retired), so remount is just a kickstart.
    restore snapshot dest="/"                         # `just restore a81c9de1 ~/Restore`  to the specified target (expanded preserving structure) [alias: unarchive]

    [Build]
    build-all *args                                   # Build every flake package available on this architecture
    check-all *args                                   # Build every flake check available on this architecture
    gen action="" a="" b=""                           # List or compare system generations.
    maintain                                          # Update, upgrade, rebuild, and garbage-collect
    rebuild force=""                                  # Rebuild the system and user configuration. `just rebuild force` activates even when nothing changed
    recovery-iso                                      # Build the non-destructive NixOS recovery ISO (Linux builder required)
    rollback gen=""                                   # Roll back to the previous or selected system generation.
    update *inputs                                    # Update flake inputs, then rebuild.
    upgrade                                           # Upgrade all package layers.

    [Clean]
    gc                                                # GC all layers at once (only regenerable caches; Trash and whole-home deletion are in gc-deep)
    gc-deep                                           # Interactively delete heavy regenerable data (Trash / ~/tmp scratch / zap of retired casks / CoreSimulator cache / podman / old build artifacts)
    tidy-apps                                         # Hide backstage apps (Adobe helpers, Karabiner's driver manager) from the Applications launcher

    [Homelab]
    dns *flags                                        # Diff the repo's declarations against Cloudflare DNS: A records, tunnel CNAMEs, and mail (MX/SPF/DKIM)
    esphome                                           # Validate the ESPHome device configs without hardware
    nextdns cmd="diff"                                # Fetch, diff, or apply the NextDNS profile. Needs NEXTDNS_API_KEY / NEXTDNS_PROFILE
    tailnet cmd="diff"                                # Fetch, diff, or apply the tailnet policy file (ACL / split DNS). Needs TS_API_KEY
    wsl-tarball flake="github:gapul/dotfiles?dir=nix" # Build the NixOS-WSL rootfs tarball on homeserver and bring it back (mac can't build it)

    [Inspect]
    check what=""                                     # Type-check / show diff  (`just check` = syntax/type-check, `just check diff` = diff build)
    doctor format=""                                  # Environment health check (run after e.g. a Determinate upgrade)
    fmt                                               # Format code + lint across all tracked files (OS auto-detected: Mac/Linux=pre-commit, Win=PSScriptAnalyzer)
    outdated                                          # List what can be updated (preview before upgrade; brew + mas + flake inputs; non-destructive)
    search query scope=""                             # Package search (`just search <q>` = brew+nixpkgs, `just search <q> all` = + cargo)

    [Mobile]
    android-apps cmd="status"                         # Diff apps.tsv against the device, or converge it (`just android-apps` / `install` / `verify` / `obtainium`)
    android-launcher-theme                            # Generate the Kvaesitso launcher theme from palettes.json and push it to the device
    android-os *flags                                 # Apply the declared Android OS settings over adb (`just android-os` = diff + apply, `just android-os --dry-run`)
    ios-apps cmd="status"                             # Diff ios/apps.tsv against a USB-connected iPhone (`just ios-apps` / `just ios-apps verify`)
    ios-profiles port="8000"                          # Build the declared .mobileconfig profiles and serve them on the LAN for an iPhone to install
    ios-shortcuts cmd="status"                        # Export iCloud-synced Shortcuts into the repo, or compile .cherri sources into signed shortcuts
    mobile-test                                       # Self-check both platforms' scripts with stubbed adb / ideviceinstaller (no device needed)

    [Service]
    restart what="bar"                                # Restart the menu-bar/WM stack (`just restart`=bar-related / individual: sketchybar|borders|omniwm / all=everything)

    [Setup]
    claude-settings-adopt                             # Adopt this machine's Claude Code settings into the remote-managed keys (client wins)
    dev what=""                                       # devShell (`just dev`=enter [shellcheck/statix available] / `just dev install`=install hooks only [non-interactive])
    docs                                              # Run this after changing a recipe/hook/alias. CI drift detection is handled by check-generated.sh.
    obsidian-snapshot                                 # One-way snapshot of Obsidian config into public dotfiles (tracking-only, vault->dotfiles)
    plist-sync                                        # Sync GUI app preference changes back into dotfiles (live -> repo)
    ssh host                                          # Use remote-env on another host

    [Theme]
    theme name=""                                     # Render all environments with the current active in palettes.json (`just theme rose-pine-dawn` also switches active)

    [Windows]
    win-autostart-glazewm *flags                      # Pass `-Unregister` (delete the task) via `*flags`
    win-bootstrap *flags                              # Run the native Windows bootstrap (`just win-bootstrap` / `just win-bootstrap -DryRun`)
    win-fmt                                           # Lint Windows-related .ps1 with PSScriptAnalyzer (exit 1 on Warning or above)
    win-fonts *flags                                  # Pass `-DryRun` `-Force` (overwrite existing too) via `*flags`
    win-keymap *flags                                 # Pass `-DryRun` `-Clear` (delete Scancode Map and return to standard) via `*flags`
    win-locale *flags                                 # Pass `-DryRun` `-SkipLanguageList` `-SkipSystemLocale` `-SkipHomeLocation` via `*flags`
    win-privacy *flags                                # Pass `-DryRun` `-SkipWinUtil` `-SkipWin11Debloat` via `*flags`
    win-scoop *flags                                  # Pass `-DryRun` `-SkipBuckets` `-SkipApps` via `*flags`
    win-status *flags                                 # Diff between apps.json (declaration) and winget list (actual install). exit 1 if any MISSING
    win-theme *flags                                  # Pass `-DryRun` `-ActivePalette rose-pine-dawn` etc. via `*flags`
    win-upgrade                                       # Upgrade every app installed via winget (--silent --accept-*)
    win-verify *flags                                 # Verify every PackageIdentifier in winget/apps.json exists (`just win-verify` / `just win-verify -Strict`)

    [secrets]
    secrets cmd="edit" file="common"                  # Files are split per host since #393: common / darwin / homelab, each with its own recipients.
```
<!-- END just-list -->

### Search

| Command | What it does |
|---|---|
| `nh search <name>` | Search nixpkgs, e.g. `nh search firefox` |

### Remote

| Command | What it does |
|---|---|
| `nssh user@host` | nvim, yazi and tmux with your own config, through rootless Nix (`nix-portable`) |
| `just ssh <host>` | Shorthand for `nssh` |
| `herdr --remote user@host` | Same preparation, then connect with herdr. A zsh function runs `configs/bin/remote-bootstrap` first. |

### Code quality

Hooks and formatters are declared in `nix/flake.nix` through git-hooks.nix and treefmt-nix.

| Command | What it does |
|---|---|
| `nix fmt` | Format nix (nixfmt) and shell (shfmt). Run it inside `nix/`. |
| `nix develop ./nix` | Enter the devShell. Generates `.pre-commit-config.yaml` and installs `.git/hooks`. |
| `nix flake check ./nix` | Run `checks.pre-commit` over `nix/`, the same check CI runs |
| `nix develop ./nix -c pre-commit run --all-files` | Run the hooks across the whole repo |
| `nix develop ./nix -c shellcheck scripts/*.sh` | Check shell by hand |
| `nix run nixpkgs#statix -- check nix` | Lint nix by hand. Not enforced. |

Hooks that run on commit, from `.git/hooks/pre-commit`. Generated from `preCommit.hooks`
in `nix/flake.nix`; run `just docs` after changing one.

<!-- BEGIN hooks -->
| Hook | Target | Excluded | What it does |
|---|---|---|---|
| `deadnix` | `*.nix` | — | Finds unused code. Module arguments like `{ lib, ... }` are allowed. |
| `gitleaks` | all staged | — | Secret detection |
| `nixfmt` | `*.nix` | — | Formatting check. Fails on anything unformatted. |
| `shellcheck` | all staged | `configs/wm/sketchybar/.*`, `\.envrc$`, `\.zsh$`, `configs/macmini/bin/.*`, `configs/macmini/client/.*`, `configs/macmini/setup-scripts/.*` | Shell lint, following .shellcheckrc |
<!-- END hooks -->

Notes:

- To change a hook, edit `preCommit.hooks` in `nix/flake.nix`, then re-enter `nix develop` to regenerate.
- `.pre-commit-config.yaml` is generated and depends on store paths. It is gitignored and untracked;
  run `nix develop ./nix` after forking to produce it.
- The flake lives in `nix/`, not at the repo root, so the `treefmt` hook cannot find the root from
  there. Formatting uses the per-file `nixfmt-rfc-style` hook instead, and `treefmt` is reserved
  for `nix fmt`.
- `shellcheck` is enforced. The excluded sketchybar configs can still be checked by hand with
  `nix develop ./nix -c shellcheck configs/wm/sketchybar/...`.
- CI runs through `om ci` (omnix). Building the `checks.pre-commit` output from git-hooks.nix
  applies the same hooks to the whole repo. `om.yaml` and the flake outputs are the single source
  of truth; `.github/workflows/ci.yml` is a thin adapter that maps system to runner and calls
  `om ci run`.

### Recovery and maintenance

| Command | What it does |
|---|---|
| `just doctor` | Health check: `/nix` mount, Login Items, fstab state |
| `sudo /usr/local/bin/determinate-nixd init` | When `/nix` is missing after a macOS update |
| `sudo /usr/local/bin/determinate-nixd upgrade` | Update the Determinate Nix runtime. Every few months. |
| `nh darwin switch` | Rebuild the system only, half of `just rebuild` |
| `nh home switch` | Rebuild the user configuration only |
| `nh clean all` | Delete old generations |

## Things worth knowing

- The Nix runtime is Determinate Nix. nix-darwin coexists with it through `nix.enable = false`.
- nix-darwin and home-manager are kept separate to avoid the USER check bug,
  [nix-darwin#1462](https://github.com/nix-darwin/nix-darwin/issues/1462).
- After editing anything under `configs/`, remember to `git add` it. A Nix flake only sees
  git-tracked files.
- Configs that applications write back to, such as nvim and karabiner, use `mkOutOfStoreSymlink`
  so GUI and CLI edits land in the repo.
- Secrets are decrypted by sops-nix and need `~/.config/sops/age/keys.txt`. Keep a copy in
  Bitwarden.
- For per-language dev shells, copy `templates/<stack>/` into a project and run `direnv allow`.

## Why `/nix` is decrypted and `noauto` is removed from fstab

Determinate Nix ships this arrangement by default:

1. the `/nix` volume is encrypted with FileVault,
2. `/etc/fstab` carries `noauto`, and
3. the launchd daemon `org.nixos.darwin-store` mounts it lazily.

That assumes everything starts from a launchd daemon, which nix-darwin's PR #1052 wraps in
`wait4path`. Login Items, GUI session restore and restored Terminal windows are outside that
wrapper. With Ghostty, AeroSpace and sketchybar running as Login Items, `/nix` is not mounted
yet when they start, and they fail to read their configs.

This is a long-standing community problem rather than a local mistake; see
[LnL7/nix-darwin#774](https://github.com/LnL7/nix-darwin/issues/774), where one user wraps the
login shell in a C program and another gave up on installing yabai through Nix.

What is done here instead:

- decrypt the volume with `diskutil apfs decryptVolume "Nix Store"`,
- remove `noauto` from `/etc/fstab` so macOS `automountd` mounts it early in boot,
- and by the time Login Items start, `/nix` is already there.

The trade-off is that this is outside Determinate's supported configuration, so an upgrade may
write `noauto` back — `bootstrap.sh` corrects that — and the volume is no longer encrypted.
Losing that encryption costs nothing here: `/nix` holds public nixpkgs binaries, and the machine
itself is covered by FileVault.

`bootstrap.sh` performs the decryption and the fstab edit on a fresh install. `just doctor`
checks both, and is worth running after a Determinate upgrade in particular.

## Troubleshooting

| Symptom | What to do |
|---|---|
| sketchybar, Ghostty or the launcher ignore their config after a reboot | Check the `/nix` mount with `just doctor`. If `noauto` came back, `sudo sed -i '' 's/,noauto//' /etc/fstab` |
| `/nix` is missing, or the shell errors out | `sudo determinate-nixd init`, or `sudo diskutil mount "Nix Store"` |
| `nh: more values required` | Open a new terminal. The old environment is inherited through `__HM_SESS_VARS_SOURCED`. |
| `git push` fails | The dotfiles remote uses SSH. Check `~/.ssh/config`. |
| A pre-commit hook blocks the commit | Leaks are shown redacted. For a false positive, add an allowlist entry to `.gitleaks.toml`. |
| `darwin-rebuild switch` fails with a USER error | nix-darwin#1462. Use `just rebuild`, which goes through nh. |
| Some Ghostty settings are ignored and stay at their defaults, such as `quick-terminal-position` | Ghostty 1.3.1 stops parsing at the first invalid line, for example `quick-terminal-screen = mouse` or `global:f18=...`. Check what actually applied with `+show-config`, then delete config lines from the top until the culprit shows up. |
