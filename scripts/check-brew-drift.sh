#!/usr/bin/env bash
set -euo pipefail

repo=${DOTFILES_DIR:-"$HOME/.dotfiles"}
flake="$repo/nix"
user=$(nix eval --raw -f "$flake/user.nix" username)
attr="darwinConfigurations.$user.config.homebrew"

declared_brews=$(nix eval --json "$flake#$attr.brews" | jq -r '.[] | (if type == "string" then . else .name end) | split("/")[-1]' | sort -u)
declared_casks=$(nix eval --json "$flake#$attr.casks" | jq -r '.[] | (if type == "string" then . else .name end) | split("/")[-1]' | sort -u)
installed_brews=$(brew leaves 2>/dev/null | awk -F/ '{ print $NF }' | sort -u)
installed_casks=$(brew list --cask 2>/dev/null | sort -u)

missing_brews=$(comm -23 <(printf '%s\n' "$declared_brews") <(brew list --formula 2>/dev/null | sort -u))
missing_casks=$(comm -23 <(printf '%s\n' "$declared_casks") <(printf '%s\n' "$installed_casks"))
extra_brews=$(comm -13 <(printf '%s\n' "$declared_brews") <(printf '%s\n' "$installed_brews"))
extra_casks=$(comm -13 <(printf '%s\n' "$declared_casks") <(printf '%s\n' "$installed_casks"))

to_json() { jq -Rsc 'split("\n") | map(select(length > 0))'; }

if [[ ${1:-} == --json ]]; then
  jq -n \
    --argjson missingBrews "$(printf '%s' "$missing_brews" | to_json)" \
    --argjson missingCasks "$(printf '%s' "$missing_casks" | to_json)" \
    --argjson extraBrews "$(printf '%s' "$extra_brews" | to_json)" \
    --argjson extraCasks "$(printf '%s' "$extra_casks" | to_json)" \
    '{ok: (($missingBrews + $missingCasks + $extraBrews + $extraCasks) | length == 0), missing: {formulae: $missingBrews, casks: $missingCasks}, extra: {formulae: $extraBrews, casks: $extraCasks}}'
else
  show() { local title=$1 value=$2; printf '  %-18s' "$title"; if [[ -n $value ]]; then printf '\n%s\n' "$value" | sed 's/^/    /'; else echo ' none'; fi; }
  show 'missing formulae:' "$missing_brews"
  show 'missing casks:' "$missing_casks"
  show 'extra formulae:' "$extra_brews"
  show 'extra casks:' "$extra_casks"
fi

[[ -z $missing_brews && -z $missing_casks && -z $extra_brews && -z $extra_casks ]]
