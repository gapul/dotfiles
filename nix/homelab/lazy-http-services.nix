{
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    attrNames
    concatMapAttrs
    mapAttrs
    mapAttrsToList
    mkForce
    mkMerge
    ;

  # One table defines the memory-reclaimable surface. Public ports stay stable;
  # containers move to loopback-only high ports hidden behind systemd sockets.
  groups = {
    archivebox = {
      containers.archivebox.pull = "missing";
      endpoints.http = {
        listen = "8000";
        upstreamPort = 18000;
      };
      idleTimeout = "15min";
      startupTimeout = 120;
    };
    filestash = {
      containers.filestash.pull = "missing";
      endpoints.http = {
        listen = "127.0.0.1:8099";
        upstreamPort = 18099;
      };
      idleTimeout = "15min";
      startupTimeout = 120;
    };
    formera = {
      containers = {
        # Built by Nix rather than pulled from a registry.
        formera-backend.pull = "never";
        formera-frontend.pull = "missing";
      };
      endpoints = {
        backend = {
          listen = "127.0.0.1:8100";
          upstreamPort = 18100;
        };
        frontend = {
          listen = "127.0.0.1:8101";
          upstreamPort = 18101;
        };
      };
      idleTimeout = "10min";
      startupTimeout = 120;
    };
    gameyfin = {
      containers.gameyfin.pull = "missing";
      endpoints.http = {
        listen = "8092";
        upstreamPort = 18092;
      };
      idleTimeout = "30min";
      startupTimeout = 120;
    };
    homepage = {
      containers = {
        glances.pull = "missing";
        homepage.pull = "missing";
      };
      endpoints.http = {
        listen = "3000";
        upstreamPort = 18300;
      };
      idleTimeout = "15min";
      startupTimeout = 120;
    };
    jellyfin = {
      containers.jellyfin.pull = "missing";
      endpoints.http = {
        listen = "8096";
        upstreamPort = 18096;
      };
      idleTimeout = "30min";
      startupTimeout = 120;
    };
    navidrome = {
      containers.navidrome.pull = "missing";
      endpoints.http = {
        listen = "4533";
        upstreamPort = 18533;
      };
      idleTimeout = "30min";
      startupTimeout = 120;
    };
    # Paperless sleeps between uses: the web UI wakes it, the consume inbox wakes it
    # (paperless.nix has a path unit), and backup.nix starts it for the sqlite dump.
    # Startup runs migrations and the OCR-remote check, so give it longer to answer.
    paperless = {
      containers = {
        paperless.pull = "missing";
        paperless-redis.pull = "missing";
      };
      endpoints.http = {
        listen = "127.0.0.1:8097";
        upstreamPort = 18097;
      };
      idleTimeout = "15min";
      startupTimeout = 180;
    };
    pingvin-share = {
      containers.pingvin-share.pull = "missing";
      endpoints.http = {
        listen = "8094";
        upstreamPort = 18094;
      };
      idleTimeout = "10min";
      startupTimeout = 120;
    };
    rallly = {
      containers = {
        rallly.pull = "missing";
        rallly-db.pull = "missing";
      };
      endpoints.http = {
        listen = "8089";
        upstreamPort = 18089;
      };
      idleTimeout = "10min";
      startupTimeout = 120;
    };
    readeck = {
      containers.readeck.pull = "missing";
      endpoints.http = {
        listen = "8087";
        upstreamPort = 18087;
      };
      idleTimeout = "15min";
      startupTimeout = 120;
    };
    romm = {
      containers = {
        romm.pull = "missing";
        romm-db.pull = "missing";
      };
      endpoints.http = {
        listen = "8091";
        upstreamPort = 18091;
      };
      idleTimeout = "30min";
      startupTimeout = 120;
    };
    spliit = {
      containers = {
        spliit.pull = "missing";
        spliit-db.pull = "missing";
      };
      endpoints.http = {
        listen = "8090";
        upstreamPort = 18090;
      };
      idleTimeout = "10min";
      startupTimeout = 120;
    };
  };

  targetUnits = map (name: "lazy-${name}.target") (attrNames groups);

  # Health of the lazy groups, reported to gatus once a day instead of polled.
  #
  # gatus used to probe these through their public ports every hour. Each probe
  # woke the group, and with idle timeouts of 10–30 minutes every group was
  # awake for a sixth to a half of each hour, all of them starting at the same
  # minute — on a fanless N150 that was the bulk of the heat (2026-10-13).
  #
  # container-auto-update already wakes every group once a day, so the check
  # rides on that: probe each upstream port directly (not the public socket,
  # which would start the proxy and hold the group up for its idle timeout) and
  # push the result to a gatus external endpoint. A group that is broken but
  # unused is noticed within a day; one that fails on a real wake still shows up
  # as a failed proxy unit in journal-alert.
  lazyHealthReport = pkgs.writeShellApplication {
    name = "lazy-health-report";
    bashOptions = [ "nounset" ];
    text = ''
      push() { # group success error
        curl -fsS --max-time 10 -o /dev/null -X POST \
          -H "Authorization: Bearer $GATUS_PUSH_TOKEN" \
          "http://127.0.0.1:8084/api/v1/endpoints/lazy_$1/external?success=$2&error=$3" \
          || echo "lazy-health-report: push for $1 failed" >&2
      }
      # Same readiness rule as the proxy's ExecStartPre: any HTTP answer below 500.
      probe() { # port timeout
        deadline=$((SECONDS + $2))
        while [ "$SECONDS" -lt "$deadline" ]; do
          status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
            "http://127.0.0.1:$1/" 2>/dev/null || true)"
          if [ "''${status:-000}" -ge 100 ] && [ "''${status:-000}" -lt 500 ]; then
            return 0
          fi
          sleep 1
        done
        echo "last status ''${status:-000}"
        return 1
      }
      ${lib.concatStrings (
        mapAttrsToList (groupName: group: ''
          err=""
          ${lib.concatStrings (
            mapAttrsToList (endpointName: endpoint: ''
              if ! out=$(probe ${toString endpoint.upstreamPort} ${toString group.startupTimeout}); then
                err="$err ${endpointName}:${toString endpoint.upstreamPort}($out)"
              fi
            '') group.endpoints
          )}
          if [ -z "$err" ]; then
            push ${groupName} true ""
          else
            echo "lazy-health-report: ${groupName} not ready:$err" >&2
            push ${groupName} false "not%20ready"
          fi
        '') groups
      )}
    '';
  };

  mkGroup =
    groupName: group:
    let
      targetName = "lazy-${groupName}";
      containerUnits = map (name: "podman-${name}.service") (attrNames group.containers);

      mkEndpoint =
        endpointName: endpoint:
        let
          proxyName = "${targetName}-${endpointName}";
          waitForUpstream = pkgs.writeShellApplication {
            name = "${proxyName}-wait";
            bashOptions = [
              "errexit"
              "nounset"
            ];
            text = ''
              deadline=$((SECONDS + ${toString group.startupTimeout}))
              while [ "$SECONDS" -lt "$deadline" ]; do
                status="$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' \
                  --max-time 1 http://127.0.0.1:${toString endpoint.upstreamPort}/ 2>/dev/null || true)"
                # A login redirect, 401 or 404 still proves that the application
                # is ready. Only connection failures and server errors keep the
                # first client queued on the systemd socket.
                if [ "''${status:-000}" -ge 100 ] && [ "''${status:-000}" -lt 500 ]; then
                  exit 0
                fi
                ${pkgs.coreutils}/bin/sleep 0.25
              done
              echo "${proxyName}: upstream did not become ready within ${toString group.startupTimeout}s" >&2
              exit 1
            '';
          };
        in
        {
          systemd.sockets.${proxyName} = {
            description = "Wake ${groupName} on incoming ${endpointName} connections";
            wantedBy = [ "sockets.target" ];
            socketConfig = {
              ListenStream = endpoint.listen;
              NoDelay = true;
            };
          };

          systemd.services.${proxyName} = {
            description = "On-demand proxy for ${groupName} ${endpointName}";
            requires = [ "${targetName}.target" ];
            after = [ "${targetName}.target" ];
            serviceConfig = {
              Type = "simple";
              ExecStartPre = lib.getExe waitForUpstream;
              ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=${group.idleTimeout} 127.0.0.1:${toString endpoint.upstreamPort}";
              DynamicUser = true;
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectHome = true;
              ProtectSystem = "strict";
            };
          };
        };
    in
    mkMerge [
      {
        virtualisation.oci-containers.containers = mapAttrs (_: container: {
          autoStart = false;
          inherit (container) pull;
        }) group.containers;

        systemd.targets.${targetName} = {
          description = "On-demand ${groupName} container group";
          requires = containerUnits;
          after = containerUnits;
          unitConfig.StopWhenUnneeded = true;
        };

        systemd.services = concatMapAttrs (containerName: _: {
          "podman-${containerName}" = {
            partOf = [ "${targetName}.target" ];

            # The only thing allowed to wake these containers is the lazy target.
            #
            # Each service module also declares wantedBy = compose-<group>-root.target
            # (inherited from compose2nix). Those targets are not wanted by anything
            # anymore, but a target that was active in an earlier generation stays
            # active forever — nothing stops it when its wantedBy link disappears.
            # jellyfin's has been active since 2026-08-11, romm's since 2026-08-23.
            #
            # switch-to-configuration restarts every active target on every switch,
            # and starting a target pulls up its Wants. So each rebuild cold-started
            # the whole lazy set behind our back. That is how 2026-09-13 broke:
            # romm-db came up mid-switch, podman fires the first healthcheck ~0.2s
            # after start, MariaDB needs ~11s, and the transient healthcheck unit
            # sat in "failed" while switch-to-configuration took its final census.
            # The switch had actually succeeded; it exited 4 anyway, so
            # nixos-upgrade.service stayed failed and journal-alert paged every
            # 15 minutes until the next upgrade run.
            #
            # --health-start-period does not help: it keeps the container status at
            # "starting" but `podman healthcheck run` still exits 1, so the unit
            # still fails (verified against podman 5.8.6).
            wantedBy = mkForce [ ];
            # podman stop terminates conmon with SIGTERM (128 + 15). Treat that
            # expected sleep transition as clean so journal-alert does not page.
            serviceConfig.SuccessExitStatus = [
              137
              143
            ];
          };
        }) group.containers;
      }
      (mkMerge (mapAttrsToList mkEndpoint group.endpoints))
    ];
in
{
  config = mkMerge (
    mapAttrsToList mkGroup groups
    ++ [
      {
        # Stopped containers are invisible to `podman auto-update`. Wake every
        # lazy group for the duration of the daily updater so rolling tags still
        # use Podman's built-in failed-start rollback. StopWhenUnneeded returns
        # each group to sleep afterwards, unless a real client still needs it.
        systemd.services.container-auto-update = {
          wants = targetUnits ++ [ "lazy-health-report.service" ];
          after = targetUnits;
        };

        # Ordered after the updater so it sees the containers it left running,
        # and wanting the targets itself keeps the groups up until it is done.
        systemd.services.lazy-health-report = {
          description = "Report lazy container groups' health to gatus";
          wants = targetUnits;
          after = targetUnits ++ [ "container-auto-update.service" ];
          path = [
            pkgs.curl
            pkgs.coreutils
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe lazyHealthReport;
            EnvironmentFile = "/var/lib/secrets/gatus.env";
          };
        };

        services.gatus.settings.external-endpoints = mapAttrsToList (groupName: _: {
          name = groupName;
          group = "lazy";
          token = "\${GATUS_PUSH_TOKEN}";
          # Daily 05:00 plus up to 20 minutes of RandomizedDelaySec and the update itself.
          heartbeat.interval = "25h";
          alerts = [
            {
              type = "ntfy";
              failure-threshold = 1;
              send-on-resolved = true;
              enabled = true;
            }
          ];
        }) groups;
      }
    ]
  );
}
