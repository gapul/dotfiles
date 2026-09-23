{ pkgs, lib, ... }:
# Site change watcher: urlwatch on an hourly systemd timer, diffs pushed to ntfy.
#
# To watch another page, append an entry to `jobs` and deploy. Each entry is one urlwatch job
# (https://urlwatch.readthedocs.io/en/latest/jobs.html); the attrset is emitted as JSON, which
# urlwatch reads as YAML. A newly added job reports once as NEW, which doubles as a deploy check.
# Useful filters (applied in order, https://urlwatch.readthedocs.io/en/latest/filters.html):
#   { html2text = "re"; }                      whole page as text
#   { css = "main"; } / { xpath = "//h1"; }    narrow to an element first
#   { grep = "pattern"; } / { grepi = ... }    keep (drop) matching lines
#   { "re.sub" = { pattern = ...; repl = ...; }; }
#   { shellpipe = "${pkgs.jq}/bin/jq -r ..."; } JSON endpoints
# Pages that only render in a browser need `browser` jobs (playwright); not enabled here.
let
  jobs = [
    # --- RISC-V Day Tokyo 2026 Autumn (2026-11-11). Track A (digital tutorial) is announced
    # but has no ticket yet. Drop these three after the event.
    {
      name = "RISC-V Day 2026 Autumn: event page";
      url = "https://riscv.or.jp/risc-v-day-tokyo-2026-autumn/";
      headers.User-Agent = "Mozilla/5.0";
      filter = [
        { grep = "article:modified_time"; }
        {
          "re.sub" = {
            pattern = ''^.*(article:modified_time" content="[^"]*").*$'';
            repl = ''\1'';
          };
        }
      ];
    }
    {
      name = "RISC-V Day 2026 Autumn: tutorial page";
      url = "https://riscv.or.jp/risc-v-day-tokyo-2026-autumn-tutorials-2/";
      headers.User-Agent = "Mozilla/5.0";
      filter = [
        { grep = "article:modified_time"; }
        {
          "re.sub" = {
            pattern = ''^.*(article:modified_time" content="[^"]*").*$'';
            repl = ''\1'';
          };
        }
      ];
    }
    {
      name = "RISC-V Day 2026 Autumn: Peatix tickets";
      url = "https://peatix.com/event/5190001/get_view_data";
      headers = {
        User-Agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36";
        Accept = "application/json";
        Referer = "https://peatix.com/event/5190001";
      };
      # seatsSold/seatsAvailable are not reliable while a ticket is closed for sale, so the list
      # is reported as-is rather than interpreted.
      filter = [
        {
          shellpipe = ''${pkgs.jq}/bin/jq -r '.json_data.event.tickets[] | "\(.name) | status \(.status) | \(.seatsAvailable)/\(.seatsMax)"' '';
        }
      ];
    }
  ];

  # One YAML document per job; JSON is a YAML subset so toJSON needs no escaping rules of its own.
  urls = pkgs.writeText "site-watch-urls.yaml" (
    lib.concatMapStringsSep "\n---\n" builtins.toJSON jobs
  );

  # urlwatch 2.29 in nixpkgs predates the built-in ntfy reporter; the shell reporter pipes the
  # text report into this. NTFY_TOKEN/NTFY_TOPIC come from gatus.env like the other alerts.
  notify = pkgs.writeShellScript "site-watch-notify" ''
    body=$(${pkgs.coreutils}/bin/cat)
    [ -n "$body" ] || exit 0
    exec ${pkgs.curl}/bin/curl -fsS --max-time 15 \
      -H "Authorization: Bearer $NTFY_TOKEN" \
      -H "Title: site-watch" \
      -H "Tags: bell" \
      -H "Priority: high" \
      --data-binary "$body" \
      "http://127.0.0.1:8082/$NTFY_TOPIC" -o /dev/null
  '';

  config = pkgs.writeText "site-watch-config.yaml" ''
    display: {new: true, error: true, unchanged: false, empty-diff: true}
    report:
      text: {details: true, footer: false, line_length: 75, minimal: false}
      stdout: {enabled: true, color: false}
      shell: {enabled: true, command: ['${notify}'], ignore_stdout: true, ignore_stderr: false}
    job_defaults: {all: {}, shell: {}, url: {}, browser: {}}
  '';
in
{
  systemd.services.site-watch = {
    description = "urlwatch: watched pages → ntfy";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "site-watch";
      EnvironmentFile = "/var/lib/secrets/gatus.env";
      # urlwatch silently drops shell jobs and shellpipe filters when the urls file lives in a
      # group/world-writable directory, which /nix/store (1775) is. Serve it from the state dir.
      ExecStartPre = "${pkgs.coreutils}/bin/install -m 0600 ${urls} /var/lib/site-watch/urls.yaml";
      ExecStart = "${pkgs.urlwatch}/bin/urlwatch --urls /var/lib/site-watch/urls.yaml --config ${config} --cache /var/lib/site-watch/cache.db";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  systemd.timers.site-watch = {
    description = "Check watched pages hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
      RandomizedDelaySec = "5min";
      Persistent = true;
    };
  };
}
