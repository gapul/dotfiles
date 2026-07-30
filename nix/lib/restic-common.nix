# Single source of truth (SSO) for restic backups.
#
# The darwin version (home/restic-backup.nix, launchd), the linux version
# (home/restic-backup-linux.nix, systemd) and the backup recipes in Justfile all
# pull the same values from here.
#
# Important: repository / forget retention policy / archive tag must be kept
#   identical across all hosts to avoid corrupting the "shared restic repository"
#   (Mac and pve share the same repo — restic shared repo). This is the sole
#   definition point, so a change here propagates to both hosts + Justfile.
{ home }:
rec {
  repository = "rclone:google-drive:restic-backup";
  rcloneConf = "${home}/.config/rclone/rclone.conf";
  passwordFile = "${home}/.config/restic/password";

  # Marker tag for cold archives. just archive adds it via --tag, forget retains it via --keep-tag.
  # If the adding side (Justfile) and the retaining side (forgetInvocation below) drift apart, cold gets treated as warm and is pruned.
  archiveTag = "archive";

  # forget retention policy invocation (shared by both hosts' backupScript).
  #   --keep-tag archive: cold archives are kept forever. Only warm (untagged) snapshots are thinned out.
  # Note: the indentation/newlines of this string go directly into the generated script's byte stream.
  #   Both backupScripts expand this at a 4-space indent position.
  forgetInvocation = ''
    restic forget --prune \
      --keep-tag ${archiveTag} \
      --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || true'';

  # Contents of the env file that emits the same values for Justfile / interactive shells.
  #   home-manager places it at ~/.config/restic/env and Justfile's restic_env sources it.
  envFileText = ''
    # Auto-generated (nix/lib/restic-common.nix). Do not edit by hand.
    export RESTIC_REPOSITORY="${repository}"
    export RESTIC_PASSWORD_FILE="${passwordFile}"
    export RCLONE_CONFIG="${rcloneConf}"
    export RESTIC_ARCHIVE_TAG="${archiveTag}"
  '';
}
