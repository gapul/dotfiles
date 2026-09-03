# Daily-use cheatsheet

The commands that keep this machine's CLI environment running. For the reasoning behind any of
it, see [README.md](../README.md).

---

## The six worth memorising first

| Key or command | What it does |
|---|---|
| Ctrl+G | Fuzzy-pick any ghq repo through fzf and cd into it |
| Ctrl+R | Fuzzy-search history through atuin |
| `<TAB>` | Fuzzy completion through fzf-tab, on every command |
| `just rebuild` | Run this after changing any configuration |
| `gita ll` | Branch and dirty state for every repo, on one screen |
| `tldr <cmd>` | An instant man page when you have forgotten how something works |

Those six cover most days.

---

## System management, through the Justfile

| Command | What it does |
|---|---|
| `just` | List the recipes |
| `just rebuild` | `nh darwin switch` and `nh home switch` |
| `just update` | Update the flake inputs, then rebuild |
| `just upgrade` | Bring brew, casks with `--greedy`, mas and Nix all up to date |
| `just gc` | Delete old generations and run the store GC, `--keep 5 --keep-since 7d` |
| `just check` | Syntax and type checking, without building |
| `just diff` | The difference between the running system and the flake |
| `just doctor` | Health check, worth running after a reboot or a Determinate upgrade |

---

## Files

eza and bat have already replaced ls and cat; home-manager aliases them automatically.

| What you type | What runs |
|---|---|
| `cat <file>` | bat, with syntax highlighting and line numbers |
| `ls` | eza --icons=auto --git |
| `ll` | eza -l --icons=auto --git |
| `la` | eza -a --icons=auto --git |
| `lt` | eza tree |
| `bottom`, `btm` | A system monitor TUI, replacing top |
| `gdu`, `dust`, `diskonaut` | Visualise disk usage |
| `yazi` | File manager TUI |

That table is the memorable subset. Every alias that is actually defined is in the generated
table below.

### Every alias, generated

Generated from `shellAliases` in `nix/modules/home/shell.nix` and from
`configs/shell/zshrc.common`. Regenerate with `just docs` after changing an alias. The latter
file holds the portable aliases shared between this machine and anything reached through nssh.

<!-- BEGIN aliases -->
| alias | Expands to |
|---|---|
| `..` | `cd ..` |
| `...` | `cd ../..` |
| `cfw` | `~/Developer/github.com/gapul/personal-tools/cloudflare/bin/cf-wrangler` |
| `eza` | `eza --icons auto --git --group-directories-first` |
| `g` | `git` |
| `ga` | `git add` |
| `gc` | `git commit` |
| `gl` | `git pull` |
| `gp` | `git push` |
| `gs` | `git status` |
| `la` | `eza -a` |
| `ll` | `eza -l` |
| `lla` | `eza -la` |
| `ls` | `eza` |
| `lt` | `eza --tree` |
| `ssh2` | `ssh -o ClearAllForwardings=yes` |
| `tl` | `textlint --config ~/.config/textlint/.textlintrc.json` |
| `tlf` | `textlint --config ~/.config/textlint/.textlintrc.json --fix` |
<!-- END aliases -->

---

## Getting around

| Key or command | What it does |
|---|---|
| Ctrl+G | Pick across repos through fzf, using ghq and a hand-written widget |
| `cd <TAB>` | fzf-tab, fuzzy with an eza preview |
| `z <name>` | zoxide, cd by how often you go there |
| `ghq look <repo>` | Open a subshell in that repo |

---

## Managing repos, with ghq and gita

### ghq, for placement

| Command | What it does |
|---|---|
| `ghq get owner/repo` | Clone into `~/ghq/<host>/<owner>/<repo>` |
| `ghq get <https or ssh URL>` | A URL works too |
| `ghq list` | Every managed repo, by relative path |
| `ghq list -p` | The same with full paths, for scripting |
| `ghq look <name>` | A subshell in that repo |
| `ghq root` | The value of ghq.root, `~/ghq` |

### gita, for working across all of them

| Command | What it does |
|---|---|
| `gita ll` | Branch, dirty state and last commit for every repo |
| `gita ls` | Just the names |
| `gita add <path>` | Add one |
| `gita-sync` | Re-register everything in `ghq list` with gita |
| `gita super pull` | Pull every repo |
| `gita super -- repoA repoB pull` | Only some of them |
| `gita super exec ls` | Run any command across all of them |
| `gita group add -n work repoA repoB` | Make a group |
| `gita super -g work pull` | Operate on a group |
| `gita info <repo>` | The path to that repo |

---

## Searching and completion

| Command | What it does |
|---|---|
| `<TAB>` | fzf-tab, with previews for git, cd, kill, checkout and others |
| Ctrl+R | atuin's fuzzy history search, synced across machines, global by default |
| Ctrl+R again, while searching | Cycle the filter: global, host, session, directory, workspace |
| Ctrl+S while searching | Cycle the search mode: fuzzy, prefix, fulltext |
| Tab while searching | Accept the candidate into the shell for editing, rather than running it |
| Enter while searching | Run the candidate immediately |
| `fd <pattern>` | Fast filename search |
| `rg <pattern>` | Fast grep, ripgrep |
| `fzf` | Fuzzy-pick from standard input |

---

## git

| Command | What it does |
|---|---|
| `git diff` | delta, side by side with line numbers, paged automatically |
| `g status`, `gs` | Aliases |
| `ga`, `gc`, `gp`, `gl` | add, commit, push, pull |
| `lazygit` | git TUI |
| `lazyjj` | jujutsu TUI |
| `just dev install` | Install the pre-commit hook into `.git/hooks/pre-commit`, once per new Mac |
| `just dev` | Enter the devShell, which has shellcheck and statix |

---

## Looking things up

| Command | What it does |
|---|---|
| `tldr <command>` | One screen of examples, as in `tldr tar` or `tldr ffmpeg` |
| `man <command>` | The full manual |
| `nh search <pkg>` | Search nixpkgs |
| `, <unknown-cmd>` | Try something without installing it, as in `, asciinema rec` |

---

## Secrets, through SOPS

| Command | What it does |
|---|---|
| `just secrets-edit` | Edit `secrets/secrets.yaml` transparently through sops |
| `just secrets-rekey` | Re-encrypt after changing `.sops.yaml` |

The age private key is `~/.config/sops/age/keys.txt`. Back it up in Bitwarden.

---

## Backups, archives and cloud storage

Four layers of storage. The reasoning is in the comments in `nix/home/restic-backup.nix` and
`rclone-mount.nix`.

| Layer | For | Where |
|---|---|---|
| GitHub and Forgejo | Code, which is reproducible | git. GitHub is the original, with a Forgejo mirror at home; see [HOMELAB.md](./HOMELAB.md) |
| restic warm | Files still in use, automatically and daily | `google-drive:restic-backup`, encrypted |
| restic cold | Files no longer in use, kept forever | The same repository, under `--tag archive` |
| rclone mount | Plaintext cloud storage shared with other people | `~/Sync/google-drive-{personal,school}`, no kernel extension needed |

### Warm, for files in use, daily and on demand

| Command | What it does |
|---|---|
| `just backup` | Run the warm backup now, kickstarting launchd and following the log |
| `just backup-ls` | Every snapshot; the Tags column separates warm from archive |
| `just backup-check` | Verify repository integrity with restic check |

### Cold, for archiving things off the local disk and keeping them permanently

| Command | What it does |
|---|---|
| `just archive <path>` | Push to restic, verify, then delete locally, under `--tag archive` |
| `just archive-ls` | The archived snapshots, with ID, date and original path |
| `just archive-stats` | Total archived size and file count |
| `just archive-find <pat>` | Search filenames inside the archive with restic find; no FUSE needed |

### Restoring, and the shared mounts

| Command | What it does |
|---|---|
| `just restore <id> [dest]` | Restore from a snapshot, defaulting to the original absolute path. Also `unarchive` |
| `just gdrive` | Check whether `~/Sync/google-drive-*` are mounted |
| `just gdrive remount`, `open` | Remount, or open in Finder |

Cold storage is kept permanently through restic's `--keep-tag archive` rather than by appending,
so `forget` never thins it out. The shared mounts use fuse-t over NFS, so macFUSE's kernel
extension and the recovery-mode dance are not needed, and the `restic` and
`google-drive:restic-backup` folders are excluded from the mount so they cannot be deleted by
accident.

---

## Remote machines

Four strategies, depending on what the remote is:

| Situation | Command | What it does |
|---|---|---|
| A compute node, non-root and ephemeral | `nssh user@host` | nvim, yazi and tmux through rootless Nix (`nix-portable`), unpacked on each start |
| The same, but through herdr | `herdr --remote user@host` | The zsh function runs `configs/bin/remote-bootstrap` first, so the preparation matches nssh. herdr instead of tmux |
| A long-lived Linux server, root and persistent | On the remote: `bash <(curl -sL ...bootstrap-linux.sh)` | A full Nix install, a dotfiles clone, and home-manager as `.#<user>-linux` |
| WSL2 | Inside WSL: `bash <(curl ...bootstrap-wsl.sh)` | The Linux common set plus WSL interop: clipboard, `/mnt/c/` |
| A restricted environment where Nix is impossible and appending is about all you get | From the local machine: `sync-configs-rsync.sh user@host [--full]` | rsync nvim, zsh.local and the git config across. Installs nothing |

Fetching private repos works, through ssh agent forwarding.

### The home-manager attributes

- `.#<user>` — macOS, which is this Mac
- `.#<user>-wsl` — WSL2
- `.#<user>-linux` — plain Linux, x86_64
- `.#<user>-linux-aarch64` — plain Linux on ARM, such as a Raspberry Pi

---

## Project development

### direnv and devenv

```bash
# scaffold devenv.nix in a new project
cd my-project
devenv init

# edit devenv.nix and declare the languages and services you want
nvim devenv.nix
# for example:
# { pkgs, ... }: {
#   packages = [ pkgs.nodejs_22 pkgs.postgresql ];
#   languages.javascript.enable = true;
#   services.postgres.enable = true;
# }

# auto-load through direnv
echo "use devenv" > .envrc
direnv allow
# cd in and Node and postgres start; leave and they stop
```

### nix-init, for scaffolding a flake.nix

```bash
# when you want to package something that is not in nixpkgs
nix-init --url https://github.com/nosarthur/gita
# it asks for a description, version and builder
# and writes a flake.nix that works
```

### Building browser engines: Ladybird and Servo

devShells for building engines other than WebKit on this machine. Both use Xcode's clang and the
macOS SDK, so they are darwin only. Defined in `nix/shells/browser-engines.nix`.

```bash
# Ladybird, CMake and vcpkg
nix develop ~/.dotfiles/nix#ladybird
cd ~/Developer/github.com/LadybirdBrowser/ladybird
python3 Meta/ladybird.py build
./Build/release/bin/Ladybird.app/Contents/MacOS/Ladybird https://example.com

# Servo, mach and cargo
nix develop ~/.dotfiles/nix#servo
cd ~/Developer/github.com/servo/servo
./mach build --release --media-stack dummy
./target/release/servoshell --headless --exit -o out.png https://example.com
```

Things that catch people out:

- Do not run `./mach bootstrap`; it is the one path that reaches for Homebrew. The cmake and
  pkg-config it wants are already in the devShell. Do not set `MACH_USE_NIX` either, or mach
  re-enters a `shell.nix` that cannot be evaluated on darwin.
- Enabling audio and video in Servo needs the official GStreamer packages, both the runtime and
  the devel one, installed system-wide with sudo, which puts them outside declarative
  management. They are installed on the mac mini only, so media-enabled builds happen there.
  `./mach package` bundles the GStreamer dylibs into the .app, so this machine only has to
  receive Servo.app and needs nothing installed. To build here without them, use
  `--media-stack dummy`, which means no playback.
- Ladybird's headless mode is broken on master as of August 2026: the Compositor process never
  starts, and WebContent crashes trying to connect to it. The GUI is fine.
- Do not add dependency libraries to the devShell. When they collide with what vcpkg builds for
  itself, nix wins, and the result references `/nix/store`. Nothing roots those store paths, so
  the next GC deletes them and the binary stops starting one day with a dyld "Library not
  loaded". If you suspect this, check with `otool -L` that there are no `/nix/store`
  references.
- Send heavy builds to the mac mini, which has 10 cores, 24 GB and more headroom. Both machines
  use `/Users/gapul` as home, so rsyncing `Build/release` to the same path is enough to run it.

---

## Poking around and troubleshooting

| Command | What it does |
|---|---|
| `just doctor` | Check the environment |
| `nix-tree ~/.nix-profile` | Dependency TUI, for "why is this even installed?" |
| `nix-tree /run/current-system` | The same at the system level |
| `nh clean all` | Delete old generations in one go |

---

## Emergency recovery

| Symptom | Command |
|---|---|
| `/nix` is not there | `sudo diskutil mount "Nix Store"` |
| That did not fix it | `sudo determinate-nixd init` |
| `noauto` came back in `fstab` | `sudo sed -i '' 's/,noauto//' /etc/fstab` |
| Updating Determinate itself | `sudo determinate-nixd upgrade` |
| Restore everything on a new Mac | `bash scripts/bootstrap.sh` |

---

## A typical day

```bash
# morning, open a terminal
Ctrl+R                    # pick up where yesterday left off, through atuin

# go to a project
Ctrl+G                    # choose a repo through fzf and cd into it

# see where things stand
gita ll                   # branch state across every repo
gs                        # status of the repo you are in

# edit
nvim src/<TAB>            # fuzzy completion through fzf-tab
cat README.md             # read it through bat

# diff
git diff                  # side by side, through delta

# commit
ga . && gc -m "feat: ..."
gp

# on to another repo
Ctrl+G

# try a command you do not have
, asciinema rec demo.cast # run it without installing
tldr ffmpeg               # check how it works

# after changing configuration
just rebuild

# weekend: bring everything up to date
gita super pull           # pull every repo
just upgrade              # update the whole system
```

---

## Windows: native pwsh plus WSL

The full roadmap is in [windows-roadmap.md](./windows-roadmap.md). The everyday commands, next
to their macOS equivalents:

| macOS | Windows, native |
|---|---|
| `bash scripts/bootstrap.sh` | `pwsh -File windows/bootstrap.ps1`, or `just win-bootstrap` |
| `just rebuild` | `git pull` is enough. There is no Nix; config symlinks update by re-running bootstrap |
| `just upgrade` | `winget upgrade --all` |
| `just secrets edit` | `sops $env:USERPROFILE\dotfiles\secrets\secrets.yaml` |
| `just check` | `just win-verify`, which checks the apps.json IDs exist, plus `just win-fmt` for PSScriptAnalyzer |
| `pbcopy < file` in WSL | `Get-Content file \| Set-Clipboard` |
| `xdg-open file` in WSL | `start file` in pwsh, or `explorer file` |

Functions that only exist in native pwsh, defined in profile.ps1:

| Function | What it does |
|---|---|
| `Find-DotfilesToolOverlap` | Show tools installed through both scoop and winget |
| `Get-DotfilesSecret <key>` | Decrypt a value out of secrets.yaml through SOPS |
| `Copy-DotfilesSecret <key>` | The same, into the clipboard |
| `Add-SshKey [path]` | Register a key with the Windows ssh-agent, shared with WSL |
| `wsl-here` | Enter WSL in the current directory |

SKK, the Japanese input method, is a different implementation on each system:

- macOS: macSKK with azoo-key-skkserv, in `configs/ime/skk/`
- Windows: CorvusSKK, installed automatically from `nathancorvussolis.corvusskk` in apps.json

Their settings are not synced; the dictionary can be copied from macOS.

---

## Implementation notes, for future reference

- eza, bat, delta and tealdeer are managed declaratively through home-manager's `programs.*`.
- fzf-tab comes in through `programs.zsh.plugins` as `pkgs.zsh-fzf-tab`.
- `ghq.root` is persisted through `programs.git.extraConfig.ghq.root`.
- The Ctrl+G widget is the `ghq-fzf` function inside `programs.zsh.initContent`.
- `gita-sync` is another function there, running `gita add` over everything in `ghq list`.
- gita itself comes from `uv tool install gita`, automated in `bootstrap.sh`.
- nom is wired in through a wrapper function around `nix build` that inserts
  `--log-format internal-json -v |& nom --json`.
- nh is not wrapped in nom, because it has its own TUI. The alias was withdrawn in `5d8bdac`.

To change any of this, edit `~/.dotfiles/nix/home/common.nix` and run `just rebuild`.
