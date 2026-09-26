# Version history for the Obsidian vault, kept here instead of on the laptop.
#
# The vault itself is synced by Self-hosted LiveSync (CouchDB, obsidian-couchdb.nix);
# that is replication, not history — a bad edit propagates to every device. Until
# 2026-09-26 the history came from obsidian-git committing on the Mac, which only
# ran while that machine was awake and unlocked. This takes the job over: Syncthing
# carries a read-only copy here (see syncthing.nix) and an hourly timer commits it
# and pushes to github.com/gapul/obsidian-vault, continuing that repository's history.
#
# The git directory deliberately lives outside the synced tree (/var/lib/vault-git,
# which restic picks up with the rest of /var/lib). A .git inside the Syncthing folder
# would be replicated back to the Mac and fight with it.
#
# The deploy key (/var/lib/secrets/vault-deploy.key, "homeserver-vault" on GitHub)
# needs write access — unlike the ledger key, this one pushes.
{
  pkgs,
  ...
}:
let
  home = "/var/lib/vault-git";
  gitDir = "${home}/git";
  workTree = "/srv/syncthing/obsidian-vault";

  githubKnownHosts = pkgs.writeText "github-known-hosts" ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
  '';
  gitSsh = pkgs.writeShellScript "vault-git-ssh" ''
    exec ${pkgs.openssh}/bin/ssh -i "$CREDENTIALS_DIRECTORY/deploy-key" \
      -o IdentitiesOnly=yes -o UserKnownHostsFile=${githubKnownHosts} "$@"
  '';

  # Syncthing's own bookkeeping and macOS litter are not part of the vault.
  excludes = pkgs.writeText "vault-git-excludes" ''
    .stfolder/
    .stversions/
    .DS_Store
  '';

  commit = pkgs.writeShellScript "vault-git-commit" ''
    set -u
    export GIT_SSH_COMMAND=${gitSsh}
    git() {
      ${pkgs.git}/bin/git --git-dir=${gitDir} --work-tree=${workTree} \
        -c user.name=homeserver -c user.email=vault@gapul.net \
        -c core.excludesFile=${excludes} "$@"
    }

    # Nothing to do until Syncthing has actually placed the vault: an empty or
    # missing tree would otherwise be committed as "everything deleted".
    if [ ! -d ${workTree}/.obsidian ]; then
      echo "vault not synced yet (${workTree}/.obsidian is missing)" >&2
      exit 1
    fi

    if [ ! -d ${gitDir} ]; then
      # Continue the existing history rather than starting a new one. The clone is
      # bare-ish: no checkout, because the work tree is the synced directory.
      ${pkgs.git}/bin/git clone --bare -q git@github.com:gapul/obsidian-vault.git ${gitDir} ||
        { echo "clone failed" >&2; exit 1; }
      git config core.bare false
      git config core.logAllRefUpdates true
    fi

    git add -A || exit 1
    if git diff --cached --quiet HEAD; then
      exit 0
    fi
    git commit -q -m "vault: $(date '+%F %H:%M')" || exit 1
    git push -q origin HEAD:main
  '';
in
{
  users.users.vault-git = {
    isSystemUser = true;
    group = "vault-git";
    # Syncthing writes the tree as itself; this only needs to read it.
    extraGroups = [ "syncthing" ];
    inherit home;
  };
  users.groups.vault-git = { };

  systemd.tmpfiles.rules = [
    "d ${home} 0750 vault-git vault-git -"
  ];

  systemd.services.vault-git = {
    description = "Obsidian vault → git (commit and push)";
    serviceConfig = {
      Type = "oneshot";
      User = "vault-git";
      Group = "vault-git";
      WorkingDirectory = home;
      LoadCredential = [ "deploy-key:/var/lib/secrets/vault-deploy.key" ];
      ExecStart = commit;
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };

  systemd.timers.vault-git = {
    description = "Commit the vault hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* *:35:00";
      Persistent = true;
    };
  };
}
