{ pkgs, ... }:
# Watches RISC-V Day Tokyo 2026 Autumn (2026-11-11) for updates with urlwatch and pushes
# the diff to ntfy: the official event/tutorial pages (WordPress modified time) and the
# Peatix ticket list (the digital Track A tutorial is announced but has no ticket yet).
# X is deliberately not watched here. Remove this module after the event.
let
  urls = pkgs.writeText "riscv-day-watch-urls.yaml" ''
    name: "RISC-V Day 2026 Autumn: event page"
    url: https://riscv.or.jp/risc-v-day-tokyo-2026-autumn/
    headers: {User-Agent: "Mozilla/5.0"}
    filter:
      - grep: 'article:modified_time'
      - re.sub: {pattern: '^.*(article:modified_time" content="[^"]*").*$', repl: '\1'}
    ---
    name: "RISC-V Day 2026 Autumn: tutorial page"
    url: https://riscv.or.jp/risc-v-day-tokyo-2026-autumn-tutorials-2/
    headers: {User-Agent: "Mozilla/5.0"}
    filter:
      - grep: 'article:modified_time'
      - re.sub: {pattern: '^.*(article:modified_time" content="[^"]*").*$', repl: '\1'}
    ---
    name: "RISC-V Day 2026 Autumn: Peatix tickets"
    url: https://peatix.com/event/5190001/get_view_data
    headers: {User-Agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36", Accept: application/json, Referer: "https://peatix.com/event/5190001"}
    filter:
      # seatsSold/seatsAvailable are not reliable while a ticket is closed for sale, so any
      # change in this list is reported as-is rather than interpreted.
      - shellpipe: ${pkgs.jq}/bin/jq -r '.json_data.event.tickets[] | "\(.name) | status \(.status) | \(.seatsAvailable)/\(.seatsMax)"'
  '';

  # urlwatch 2.29 in nixpkgs predates the built-in ntfy reporter; the shell reporter pipes the
  # text report into this. NTFY_TOKEN/NTFY_TOPIC come from gatus.env like the other alerts.
  notify = pkgs.writeShellScript "riscv-day-watch-notify" ''
    body=$(${pkgs.coreutils}/bin/cat)
    [ -n "$body" ] || exit 0
    exec ${pkgs.curl}/bin/curl -fsS --max-time 15 \
      -H "Authorization: Bearer $NTFY_TOKEN" \
      -H "Title: RISC-V Day 2026 Autumn" \
      -H "Tags: bell" \
      -H "Priority: high" \
      --data-binary "$body" \
      "http://127.0.0.1:8082/$NTFY_TOPIC" -o /dev/null
  '';

  config = pkgs.writeText "riscv-day-watch-config.yaml" ''
    display: {new: true, error: true, unchanged: false, empty-diff: true}
    report:
      text: {details: true, footer: false, line_length: 75, minimal: false}
      stdout: {enabled: true, color: false}
      shell: {enabled: true, command: ['${notify}'], ignore_stdout: true, ignore_stderr: false}
    job_defaults: {all: {}, shell: {}, url: {}, browser: {}}
  '';
in
{
  systemd.services.riscv-day-watch = {
    description = "urlwatch: RISC-V Day Tokyo 2026 Autumn updates → ntfy";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "riscv-day-watch";
      EnvironmentFile = "/var/lib/secrets/gatus.env";
      ExecStart = "${pkgs.urlwatch}/bin/urlwatch --urls ${urls} --config ${config} --cache /var/lib/riscv-day-watch/cache.db";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  systemd.timers.riscv-day-watch = {
    description = "Check RISC-V Day 2026 Autumn pages hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
      RandomizedDelaySec = "5min";
      Persistent = true;
    };
  };
}
