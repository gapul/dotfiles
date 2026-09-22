{
  config,
  pkgs,
  ...
}:
# Watches RISC-V Day Tokyo 2026 Autumn (2026-11-11) for updates and pushes a ntfy
# notification: new posts by the organizer (@riscv_a) or the tutorial instructor
# (@Ishi_Kai_ASIC), a change to the official event/tutorial pages, or a change in
# the Peatix ticket list (Track A digital tutorial is announced but has no ticket yet).
# Remove this module after the event.
let
  home = config.home.homeDirectory;
  state = "${home}/.local/state/riscv-day-watch";
  # `x` (configs/bin/x, PR #658) reads X through the local twitter-api-safe relay and
  # starts it on demand. Until that PR lands it lives in its worktree.
  xFallback = "${home}/.dotfiles-worktrees/feat/x-cli/configs/bin/x";
  watch = pkgs.writeShellScript "riscv-day-watch" ''
    set -u
    export PATH="${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
    mkdir -p "${state}"
    X=$(command -v x || true); [ -n "$X" ] || X="${xFallback}"
    UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36'
    msgs=()

    notify() {
      /usr/bin/osascript -e "display notification \"$(printf %s "$1" | head -c 200 | tr '"' "'")\" with title \"RISC-V Day\"" >/dev/null 2>&1 || true
      if [ -r "${home}/.config/ntfy/url" ] && [ -r "${home}/.config/ntfy/token" ]; then
        /usr/bin/curl -fsS --max-time 15 \
          -H "Authorization: Bearer $(cat "${home}/.config/ntfy/token")" \
          -H "Title: RISC-V Day 2026 Autumn" -H "Tags: bell" -H "Priority: high" \
          --data-binary "$1" "$(cat "${home}/.config/ntfy/url")" >/dev/null 2>&1 || true
      fi
    }

    # diff <key> <current-text>: notify lines that are new since the last run (first run = baseline only).
    diff() {
      local key=$1 cur=$2 prev="${state}/$1" new
      if [ -f "$prev" ]; then
        new=$(grep -vxF -f "$prev" <<<"$cur" || true)
        [ -n "$new" ] && msgs+=("[$key]"$'\n'"$new")
      fi
      printf '%s\n' "$cur" >"$prev"
    }

    # 1. X: organizer posts (all) and instructor posts that mention RISC-V Day.
    if [ -x "$X" ]; then
      posts=$("$X" @riscv_a 20 2>/dev/null | cut -f1,2,5 | cut -c1-300 || true)
      [ -n "$posts" ] && diff x-riscv_a "$posts"
      posts=$("$X" @Ishi_Kai_ASIC 20 2>/dev/null | grep -i 'RISC-V Day' | cut -f1,2,5 | cut -c1-300 || true)
      [ -n "$posts" ] && diff x-ishikai "$posts"
    fi

    # 2. Official pages: WordPress modified time.
    for u in https://riscv.or.jp/risc-v-day-tokyo-2026-autumn/ https://riscv.or.jp/risc-v-day-tokyo-2026-autumn-tutorials-2/; do
      mod=$(/usr/bin/curl -fsSL -m 20 -A "$UA" "$u" | grep -o 'article:modified_time" content="[^"]*"' | head -1)
      [ -n "$mod" ] && diff "page-$(basename "$u")" "$u $mod"
    done

    # 3. Peatix ticket list (name / status / seats). seatsSold is not reliable while sales are
    # closed, so treat any change as news rather than interpreting the numbers.
    tickets=$(/usr/bin/curl -fsSL -m 20 -A "$UA" -H 'Accept: application/json' -H 'Referer: https://peatix.com/event/5190001' \
      https://peatix.com/event/5190001/get_view_data \
      | ${pkgs.jq}/bin/jq -r '.json_data.event.tickets[] | "\(.name) | status \(.status) | \(.seatsAvailable)/\(.seatsMax)"' 2>/dev/null || true)
    [ -n "$tickets" ] && diff peatix-tickets "$tickets"

    if [ ''${#msgs[@]} -gt 0 ]; then
      notify "$(printf '%s\n\n' "''${msgs[@]}")"
    fi
    date +%FT%T >"${state}/last-run"
  '';
in
{
  launchd.agents.riscv-day-watch = {
    enable = true;
    config = {
      ProgramArguments = [ "${watch}" ];
      StartInterval = 3600;
      RunAtLoad = true;
      ProcessType = "Background";
      StandardErrorPath = "${home}/Library/Logs/riscv-day-watch.log";
    };
  };
}
