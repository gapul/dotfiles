#!/usr/bin/env bash
# The package lane of `just upgrade` / `just maintain` on macOS: Homebrew formulae and casks,
# with Xcode, the SketchyBar font and the GitHub pins downloading alongside.
set -u
# Xcode and the SketchyBar font share nothing with Homebrew, and this link gives roughly
# twice the throughput over parallel connections as over one (measured: 20 MB/s single,
# 40 MB/s over four), so they download alongside the brew work instead of after it.
# Homebrew's own steps stay strictly serial: brew holds a lock, so a second brew process
# would only wait or fail. Output is buffered and replayed so three downloads do not
# interleave into unreadable soup.
xcode_out=$(mktemp); font_out=$(mktemp)
# </dev/null: xcodes asks for a 2FA code on stdin when the saved session has expired, and this
# lane's output is buffered, so the question is invisible and the whole maintain waits forever
# on an answer nobody was asked for. With no stdin it fails fast into the "re-run" message
# below instead. sudo is unaffected — it reads the tty directly, not stdin.
just _xcode-upgrade >"$xcode_out" 2>&1 </dev/null &
xcode_pid=$!
just sketchybar-font >"$font_out" 2>&1 &
font_pid=$!
pins_out=$(mktemp)
just github-pins >"$pins_out" 2>&1 &
pins_pid=$!
# Order matters: `brew update` resets the trust of unofficial taps, so run update
# first, then trust, and run the subsequent upgrade with HOMEBREW_NO_AUTO_UPDATE=1
# so the trust is not reset again. Skip this and update ->
# (trust lost) -> upgrade makes qmk/qmk (formula) and y3owk1n/tap/neru (cask)
# get refused as untrusted; the cask is swallowed by `|| true` and the final check fails.
brew update --quiet || true
just _brew-trust-taps
just _brew-formula-upgrade
echo "━━━ Homebrew casks"
HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --quiet --cask --greedy || true
wait $xcode_pid || true; cat "$xcode_out"; rm -f "$xcode_out"
wait $font_pid || true; cat "$font_out"; rm -f "$font_out"
wait $pins_pid || true; cat "$pins_out"; rm -f "$pins_out"
# The --greedy upgrade above also targets auto_updates/`version :latest` casks,
# but those stay "outdated" forever and can never "complete" (e.g. figma-agent,
# pear-desktop; for the latter the upstream cask errors on upgrade itself due to a
# missing URL, swallowed by `|| true`). So judge completion with outdated without --greedy.
# Non-greedy does not list auto_updates/latest, so it detects only missed real
# version updates and does not break as auto_updates casks grow (previously
# figma-agent was grep-excluded, but enumerating them breaks, so that was removed).
remaining=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --cask 2>/dev/null || true)
if [ -n "$remaining" ]; then echo "ERROR: cask upgrade incomplete:" >&2; echo "$remaining" >&2; exit 1; fi
