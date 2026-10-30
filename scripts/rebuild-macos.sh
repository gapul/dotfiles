#!/usr/bin/env bash
# `just rebuild` on macOS: build the darwin and home-manager configurations, then activate
# only what changed. `rebuild-macos.sh force` activates even when nothing did.
set -euo pipefail
force="${1:-}"
flake="$(cd "$(dirname "$0")/.." && pwd)/nix"
# Activate only what actually changed. Building both configurations costs ~7s on a tree nix has
# not evaluated yet and ~0.1s on one it has; a switch that has nothing to do still costs darwin
# ~15s (incl. the Homebrew bundle) and home ~7s. Most rebuilds — every `git
# pull` of main via the post-merge hook — change one of the two at most, and plenty change neither.
# The catch: activation is also what repairs drift made outside nix (a hand-run `brew install`,
# a `defaults write`, a launchd agent someone unloaded). Skipping means not repairing. That is
# what `just rebuild force` is for, and what `just maintain` uses.
# The configuration name: nh used to pick it by hostname, which here is MacBook-Mini while the
# attribute is named after the user, and the username is only the right answer on the
# workstation. Both Macs report the same LocalHostName, so a machine that is not the
# workstation has to say so out loud, in ~/.config/dotfiles/host (macmini declares that file
# in home/macmini.nix). Getting this wrong is not a no-op: on the mac mini it quietly activated
# the workstation config, dropping the manabi tunnel and pulling in the GUI cask list.
name="$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/host" 2>/dev/null || id -un)"
# Tee the whole run to a fixed log so a failure can be inspected after the fact
# without re-running — crucially the Homebrew bundle step, which runs during
# nix-darwin activation and so is absent from `nix log <drv>`.
log=/tmp/nix-rebuild.log
: > "$log"
# Build first, then activate the built store path directly. The changed-or-not check used to be
# `nix eval …outPath`, which the eval cache never serves (6s darwin + 9s home, one after the
# other, on every run), and nh then evaluated again for its own build. `nix build` of the
# attribute is an eval-cache hit once the tree has been evaluated, and on a fresh tree the two
# side by side take ~7s against ~10s in one invocation. The out-links are GC roots, so a nix GC
# running alongside (`just maintain` starts one) cannot collect a build before it is activated.
# The build runs under a QoS clamp so it cannot starve the desktop. `-c utility` rather than
# `-b`: background QoS parks the build on the efficiency cores, which made every rebuild several
# times slower than it needed to be. utility still yields to anything user-interactive.
roots="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
mkdir -p "$roots"
# Hosts whose home rides inside the darwin config (the mac mini) have no standalone
# homeConfigurations entry; there is nothing to activate separately. `?` never forces the value.
has_home=$(nix eval "$flake#homeConfigurations" --apply "a: a ? \"$name\"" 2>/dev/null || echo false)
home_out=$(mktemp)
home_pid=""
if [ "$has_home" = true ]; then
  taskpolicy -c utility nix build --out-link "$roots/rebuild-home" \
    "$flake#homeConfigurations.$name.activationPackage" >"$home_out" 2>&1 &
  home_pid=$!
fi
# The darwin build is the one shown live. With a TTY it goes through nix-output-monitor, as nh
# did; without one (git hooks, CI, an agent shell) plain nix keeps the log greppable instead of
# cursor-control escape soup.
sys_attr="$flake#darwinConfigurations.$name.config.system.build.toplevel"
if [ -t 1 ]; then
  taskpolicy -c utility nix build --out-link "$roots/rebuild-sys" "$sys_attr" \
    --log-format internal-json -v 2>&1 | nom --json 2>&1 | tee -a "$log"
else
  taskpolicy -c utility nix build --out-link "$roots/rebuild-sys" "$sys_attr" 2>&1 | tee -a "$log"
fi
sys_want=$(readlink "$roots/rebuild-sys")
home_want=""
if [ -n "$home_pid" ]; then
  if ! wait "$home_pid"; then
    tee -a "$log" <"$home_out" >&2; rm -f "$home_out"
    echo "home-manager build failed" >&2; exit 1
  fi
  cat "$home_out" >>"$log"
  home_want=$(readlink "$roots/rebuild-home")
fi
rm -f "$home_out"
# Activation output goes to the log only, as it did under nh: a no-op darwin activation is a
# screenful and home-manager prints a line per step. On failure the tail is shown.
activate() {
  if ! "$@" >>"$log" 2>&1; then
    tail -30 "$log" >&2; echo "activation failed (full log: $log)" >&2; exit 1
  fi
}
sys_have=$(readlink /run/current-system || true)
home_have=$(readlink "$HOME/.local/state/home-manager/gcroots/current-home" || true)
do_sys=1; do_home=1
[ -z "$home_want" ] && do_home=0
if [ -z "$force" ]; then
  [ "$sys_want" = "$sys_have" ] && do_sys=0
  [ "$home_want" = "$home_have" ] && do_home=0
fi
if [ "$do_sys" = 0 ] && [ "$do_home" = 0 ]; then
  echo "✓ already current (nothing to activate; use \`just rebuild force\` to activate anyway)"
  exit 0
fi
# (No brew trust pass here: every tap in nix/hosts/darwin.nix is `trusted = true`, so the
#  activation's `brew bundle` records the trust itself. upgrade-packages-macos.sh still runs
#  _brew-trust-taps, because its `brew update` happens outside the activation.)
if [ "$do_sys" = 1 ]; then
  echo "━━━ nix-darwin" | tee -a "$log"
  # Take sudo up front, the same way `just maintain` does. Without this the prompt lands in the
  # middle of an activation that prints nothing, so the rebuild looks frozen — and when it runs
  # without a tty (post-merge hook, an agent) it waits forever with no output at all.
  # `sudo -v` alone is wrong on a host with NOPASSWD: it still insists on a password and, with
  # no tty, fails outright — which is how the mac mini's post-merge rebuild started erroring
  # instead of activating. Ask the cheap question first and only fall back to the prompt.
  sudo -n true 2>/dev/null || sudo -v
  # What `darwin-rebuild switch` (and nh) do once the system is built: point the system profile
  # at it, then run its activation as root. (activate-user is deprecated and empty.) nh cannot
  # be handed a store path for darwin ("Nix doesn't support nix store installables"), hence by hand.
  sudo nix-env -p /nix/var/nix/profiles/system --set "$sys_want"
  activate taskpolicy -c utility sudo "$sys_want/activate"
  echo "✓ nix-darwin" | tee -a "$log"
else
  echo "– nix-darwin unchanged" | tee -a "$log"
fi
if [ -z "$home_want" ]; then
  echo "– home-manager: this host has no standalone config (it rides inside nix-darwin)" | tee -a "$log"
  open -a Ghostty >/dev/null 2>&1 || true
  exit 0
fi
echo "━━━ home-manager" | tee -a "$log"
# hm-bak: standalone home-manager has no backupFileExtension option (that one only exists on
# the nix-darwin/NixOS module path), and without a backup extension a newly declared home.file
# whose target already exists is skipped — the declaration silently does nothing. That is how
# gh-dash/config.yml and slk/config.toml stayed plain files after #153 declared them.
# The activation script records the profile generation itself.
if [ "$do_home" = 1 ]; then
  HOME_MANAGER_BACKUP_EXT=hm-bak activate taskpolicy -c utility "$home_want/activate"
  echo "✓ home-manager" | tee -a "$log"
else
  echo "– home-manager unchanged" | tee -a "$log"
fi
open -a Ghostty >/dev/null 2>&1 || true
