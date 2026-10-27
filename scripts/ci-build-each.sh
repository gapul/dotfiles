#!/usr/bin/env bash
# Build every flake output of one system, each in its own `nix build` process.
#
# This stands in for `om ci run` on GitHub's linux runner. omnix hands all outputs to a single
# nix process (devour-flake), and the evaluator keeps every evaluated NixOS configuration alive
# until the end. On x86_64-linux that adds up to roughly 25 GB (measured 2026-10-27: nixos-laptop
# 5.1, nixos-laptop-ci 5.1, nixos-smoke 3.8, wsl 2.2, homeserver 2.1, pr-gate 2.1, homeserver-vm
# 2.0, ...), and the runner has 16 GB. The kernel kills the runner itself, so the job ends with
# "The runner has received a shutdown signal" and no build log. Main had not gone green since
# 2026-08-28 for this reason. One process per output caps the peak at the largest single output.
#
# The set mirrors what omnix collects: packages, checks, devShells, nixosConfigurations whose
# system matches, and legacyPackages.<system>.homeConfigurations.
#
# Usage (from the repository root): scripts/ci-build-each.sh x86_64-linux [extra nix args...]
set -euo pipefail

system=$1
shift
flake=./nix

# Each listing is its own assignment so that, under `set -e`, a failed `nix eval` stops the
# script instead of silently shrinking the set (`< <(...)` would swallow it).
names() {
  nix eval --json "$flake#$1" --apply "$2" | jq -r --arg p "$1." --arg s "$3" '.[] | $p + . + $s'
}
all='builtins.attrNames'
# Only the configurations for this system. Reading hostPlatform costs ~0.6 GB for all of them.
same_system="cs: builtins.filter (n: cs.\${n}.pkgs.stdenv.hostPlatform.system == \"$system\") (builtins.attrNames cs)"

packages=$(names "packages.$system" "$all" "")
checks=$(names "checks.$system" "$all" "")
shells=$(names "devShells.$system" "$all" "")
homes=$(names "legacyPackages.$system.homeConfigurations" "$all" .activationPackage)
hosts=$(names nixosConfigurations "$same_system" .config.system.build.toplevel)
mapfile -t attrs < <(printf '%s\n' "$packages" "$checks" "$shells" "$homes" "$hosts" | grep .)

# Keep going past a failure so one red output doesn't hide the state of the rest, but fail the
# job at the end.
failed=()
for a in "${attrs[@]}"; do
  echo "::group::$a"
  if ! nix build "$flake#$a" --no-link --print-build-logs "$@"; then
    failed+=("$a")
  fi
  echo "::endgroup::"
done

if [ ${#failed[@]} -gt 0 ]; then
  printf '::error::build failed: %s\n' "${failed[@]}"
  exit 1
fi
echo "built ${#attrs[@]} outputs"
