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
# git is not in the winget declaration, since development happens on the WSL side.
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
# defaults: WSL is Ubuntu, the user is Windows's $env:USERNAME
& $env:USERPROFILE\dotfiles\windows\bootstrap.ps1
# for a different user or distro
& $env:USERPROFILE\dotfiles\windows\bootstrap.ps1 -WslUser alice -WslDistro Debian
```

What it does:

1. Checks winget, then installs everything in `apps.json` with `winget import`.
2. Symlinks `$PROFILE`.
3. Generates Windows Terminal's `settings.json`, substituting `__WSL_USER__` and
   `__WSL_DISTRO__`.
4. Restricts the ACL on the age and SSH keys to you alone with `icacls`, if they are present.
5. Sets the global git configuration.

- [ ] If creating symlinks fails, run as administrator or turn on developer mode, under
      Settings, Privacy and security, For developers.
- [ ] An existing `$PROFILE` or Terminal settings file is moved aside to `.bak-<timestamp>`.

## 4. Place the keys and check the permissions

- [ ] Put the age private key at `%USERPROFILE%\.config\sops\age\keys.txt`.
- [ ] Put the SSH private key at `%USERPROFILE%\.ssh\id_ed25519`.
- [ ] Run bootstrap again, so `icacls` narrows the ACLs to you alone.
- Check with `icacls $env:USERPROFILE\.ssh\id_ed25519` that only the current user is listed.
  Without this, OpenSSH refuses the key with "bad permissions".
- [ ] If you are going to sign or push, register the public key with GitHub, through
      `gh ssh-key add` or similar.

## 5. WSL2

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
- Note that the WSL profile's `startingDirectory` in Terminal was already expanded by bootstrap
  to `//wsl$/<distro>/home/<user>`. If the distro or user differs it will not open, so match
  them with `-WslDistro` and `-WslUser`.

## 6. Checking it works

- [ ] In a new PowerShell, the starship prompt looks the same as on macOS, meaning
      `$env:STARSHIP_CONFIG` points at `...\dotfiles\configs\shell\starship.toml`.
- [ ] `v` and `vim` open nvim.
- [ ] zoxide's `z` works.
- [ ] Windows Terminal defaults to the WSL (Ubuntu) profile, with a Nerd Font.
- [ ] The git aliases `g`, `gs`, `ga` and friends work.

---

## Still unresolved, to settle on the machine

**There is no native path for decrypting with SOPS.** On the native Windows side the age key is
merely placed; nothing uses it to decrypt secrets. For now the assumption is that decryption
happens on the WSL side, through sops-nix. If it becomes necessary natively, add a wrapper
around `sops -d` to the profile.

**winget can only go so far declaratively.** Import installs things but has no way to remove
what is not declared — there is no equivalent of Nix's `cleanup="uninstall"`. Unwanted apps are
uninstalled by hand.

**A more capable profile** — oh-my-posh, PSFzf, Terminal-Icons — is worth doing on the machine,
where the rendering can actually be checked.
