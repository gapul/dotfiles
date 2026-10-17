# Setting up a Windows machine

The preparation, meaning the configuration files, is already done on macOS. On the machine
itself, work through this in order, satisfying each step's check before moving on.

---

## 0. Prerequisites

- [ ] Windows 11, with PowerShell 7 (`pwsh`) available. If it is not, winget installs it below.
- [ ] Sign in with a **local account**, not a Microsoft account. Either take the "I don't have
      internet" route during OOBE, or, if you already have an MSA, switch through Settings,
      Accounts, "Sign in with a local account instead". This cannot be expressed
      declaratively, which is why it is written down here.
- [ ] Confirm BitLocker is on, with `manage-bde -status C:`. Private keys are going on this
      disk, so encryption is not optional.
- [ ] Have the age private key and the SSH private key ready, from Bitwarden or wherever they
      live.

## 1. Clone

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned   # allow local scripts
# git is not in winget/apps.json; day-to-day development happens on the NixOS side.
# Install it once by hand, just to clone:
#   winget install --exact --id Git.Git
git clone https://github.com/gapul/dotfiles.git $env:USERPROFILE\dotfiles
```

Check that `%USERPROFILE%\dotfiles\windows\bootstrap.ps1` exists.

Note that the native Windows clone goes to `%USERPROFILE%\dotfiles`, without the leading dot,
unlike `~/.dotfiles` on macOS and WSL. The asymmetry is deliberate and follows each platform's
convention.

## 2. Check the winget package IDs exist

This is the step that matters most. The IDs in `windows/winget/apps.json` were verified against
a real machine on 2026-06-26. After editing them, always run `verify.ps1`:

```powershell
pwsh -NoProfile -File $env:USERPROFILE\dotfiles\windows\winget\verify.ps1
# for CI, exiting 1 on a miss
pwsh -NoProfile -File $env:USERPROFILE\dotfiles\windows\winget\verify.ps1 -Strict
```

- [ ] `verify.ps1` reports zero MISS and zero ERR.

IDs that used to be listed here as uncertain and have since been confirmed:

- sops is `SecretsOPerationS.SOPS`; Mozilla.SOPS is the old one
- gitleaks is `Gitleaks.Gitleaks`
- typst is `Typst.Typst`
- bottom is `Clement.bottom`
- mpv is `shinchiro.mpv`
- JetBrainsMono Nerd Font is `DEVCOM.JetBrainsMonoNerdFont`, installed automatically from
  apps.json because Terminal's `fontFace` assumes it

GUI applications such as Tor Browser, Zen, Beeper and Affinity are added case by case, once you
decide on the machine whether you want them.

## 3. Run bootstrap, ideally from an administrator PowerShell

```powershell
& $env:USERPROFILE\dotfiles\windows\bootstrap.ps1 -DryRun   # the plan, no side effects
& $env:USERPROFILE\dotfiles\windows\bootstrap.ps1
```

The nine steps it runs, and the `-Skip*` switch for each, are listed in `windows/README.md`.

- [ ] If creating symlinks fails, run as administrator or turn on developer mode, under
      Settings, Privacy and security, For developers.
- [ ] An existing `$PROFILE` or config file is moved aside to `.bak-<timestamp>`.
- [ ] The privacy step (7) downloads the pinned Win11Debloat and WinUtil and refuses to run
      either one if its SHA256 does not match `windows/privacy/upstream.psd1`. It ends with
      `失敗 N 件` and exit 1 if anything failed; the full output is kept in
      `%LOCALAPPDATA%\dotfiles\privacy-apply-<timestamp>.log`.

## 4. Place the keys and check the permissions

- [ ] Put the age private key at `%USERPROFILE%\.config\sops\age\keys.txt`.
- [ ] Put the SSH private key at `%USERPROFILE%\.ssh\id_ed25519`.
- [ ] Run bootstrap again, so `icacls` narrows the ACLs to you alone.
- Check with `icacls $env:USERPROFILE\.ssh\id_ed25519` that only the current user is listed.
  Without this, OpenSSH refuses the key with "bad permissions".
- [ ] If you are going to sign or push, register the public key with GitHub, through
      `gh ssh-key add` or similar.

## 5. WSL2, only on a Windows-only machine

Skip this on the dual-boot machine: NixOS is one partition over and nothing here depends on WSL.
On a machine where Windows is the only OS:

```powershell
wsl --install -d Ubuntu        # as administrator. May need a reboot
```

Then, inside WSL:

```bash
git clone https://github.com/gapul/dotfiles.git ~/.dotfiles
~/.dotfiles/scripts/bootstrap-wsl.sh
```

- [ ] `bootstrap-wsl.sh` switches home-manager to `#homeConfigurations.<user>-wsl`.
- Check that `wslview`, `pbcopy` through clip.exe, and the `explorer` function all work.

## 6. Checking it works

- [ ] In a new PowerShell, the starship prompt looks the same as on macOS, meaning
      `$env:STARSHIP_CONFIG` points at `...\dotfiles\configs\shell\starship.toml`.
- [ ] `v` and `vim` open nvim.
- [ ] zoxide's `z` works.
- [ ] WezTerm starts with the JetBrainsMono Nerd Font.
- [ ] `just win-privacy-verify` ends with `baseline と一致`. Run it again after a feature update;
      Windows sometimes turns a task or service back on.
- [ ] The git aliases `g`, `gs`, `ga` and friends work.

---

## Still unresolved, to settle on the machine

**SOPS decryption works natively.** The profile sets `$env:SOPS_AGE_KEY_FILE` to the key from
step 4, and `Get-DotfilesSecret` / `Copy-DotfilesSecret` decrypt from `secrets/`.

**winget can only go so far declaratively.** Import installs things but has no way to remove
what is not declared — there is no equivalent of Nix's `cleanup="uninstall"`. Unwanted apps are
uninstalled by hand.

**A more capable profile** — oh-my-posh, PSFzf, Terminal-Icons — is worth doing on the machine,
where the rendering can actually be checked.
