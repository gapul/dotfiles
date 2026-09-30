# Leave container updates to podman itself.
#
# podman does not re-pull on its own, even for :latest. Even when the declaration says latest, the
# actual image stays at whatever was pulled first; when I looked on 2026-08-30, 20 of them were
# months to a year old. If the declaration says "always latest" and reality doesn't match, it is
# reality that needs fixing.
#
# Digest pinning + Renovate is not used. Pinning is the opposite of "stay on latest", and what CI
# can verify is the nix configuration, not whether a container starts, so 40 containers' worth of
# PRs every week would buy little safety.
#
# podman auto-update was chosen because rollback is built in: if a unit fails to start after an
# update, it goes back to the previous image and restarts. A home-made timer would have to build
# that.
#
# Its weakness, for the record: rollback is really meant to be decided by receiving "ready" via
# SDNOTIFY, and without that it misses the "starts, then dies right after" type. That is caught
# within 15 minutes by journal-alert's restart-loop detection (PR #490). The split is: auto-update
# rolls back instant deaths, and notifications catch delayed ones.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Put the auto-update label on every container. The declarations are spread across 28 files,
  # so instead of touching each one, set it once as the submodule default. It is mkDefault, so
  # a container that should opt out can override it in its own declaration.
  #
  # DB tags are pinned to a major version, like postgres:16-alpine / mariadb:11 / couchdb:3, so
  # breakage like jumping from 16 to 17 is already blocked at the tag level.
  # No container needs to be excluded for now.
  options.virtualisation.oci-containers.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.labels."io.containers.autoupdate" = lib.mkDefault "registry";
      }
    );
  };

  config = {
    # If the image name is not fully qualified, auto-update dies at startup with:
    #   Error: short name: auto updates require fully-qualified image reference
    #
    # This was hit in production on 2026-08-30. 14 declarations used short names like
    # `postgres:16-alpine`, and as soon as the label was added, 12 containers including ntfy,
    # vaultwarden and the DBs failed to start. Both nix evaluation and CI had passed. Right after
    # writing in the PR that CI checks the configuration, not whether containers start, I fell into
    # exactly that hole.
    #
    # So this one point is made visible to nix. It only moves a runtime failure to an evaluation-time
    # error, but at least the same mistake won't happen twice.
    #
    # It only applies to "containers auto-updated with the registry policy", though.
    # nostr-bunker.nix's signet/signet-ui override the label to disabled and never pull from a
    # registry at all (pull = "never"; a self-built image whose source image is not published
    # anywhere). podman does not refuse to start in that case, so the failure mode above does not
    # apply — without the exclusion, I'd have to invent a fully-qualified name pointing at a
    # nonexistent registry.
    assertions = lib.mapAttrsToList (name: c: {
      assertion =
        (c.labels."io.containers.autoupdate" or "registry") != "registry"
        || lib.hasInfix "." (builtins.head (lib.splitString "/" c.image));
      message = ''
        コンテナ ${name} の image "${c.image}" が完全修飾ではない。
        auto-update のラベルが付いていると podman が起動を拒否する。
        レジストリを明示すること (例: postgres:16-alpine → docker.io/library/postgres:16-alpine)。
      '';
    }) config.virtualisation.oci-containers.containers;

    systemd.services.container-auto-update = {
      description = "コンテナの image を引き直して載せ替える";
      path = with pkgs; [
        podman
        curl
        jq
        gnugrep
        gnused
        coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/container-auto-update.sh}";
      };
    };

    systemd.timers.container-auto-update = {
      description = "コンテナの更新を毎日走らせる";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Pick up rolling tags within 24 hours at most. Avoids backup (03:13) and the nightly
        # nixos-upgrade; on failure, Podman's rollback and ntfy take over.
        OnCalendar = "*-*-* 05:00";
        Persistent = true;
        RandomizedDelaySec = "20min";
      };
    };
  };
}
