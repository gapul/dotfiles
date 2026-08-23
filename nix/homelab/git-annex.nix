# git-annex remote for fonts and design assets.
#
# The files themselves are too big for git and too irregular for restic to be the
# only copy: a font or a texture is looked up by name, from whichever machine is
# in front of me, and git-annex is the one tool that keeps the *filenames* in git
# while the bytes live wherever there is room.
#
# Why this host holds them: it has the 432GB pool, and it is the only always-on
# machine, so it is the remote both Macs sync through.
#
# The licensing constraint is the reason this is worth doing at all. Commercial
# Japanese fonts may not be placed on a server, and "remember not to" is not a
# control. git-annex enforces it structurally through the preferred content
# expression on this remote:
#
#   git annex wanted homeserver 'exclude=fonts/commercial/*'
#
# After that, `git annex copy --to homeserver` will not send those files, no
# matter who runs it. The filenames still sync, so the Mac can see what exists.
#
# Nothing here creates the repository — that is one `git annex init` and belongs
# in the repo, not in the system definition. This module only provides the
# binary and a directory with the right owner.
{ pkgs, ... }:
{
  # git 本体も要る。ssh 越しの remote は git-upload-pack / git-receive-pack を
  # 呼ぶので、git-annex だけ入れても clone できない (この host には git が
  # 入っていなかった)。
  environment.systemPackages = [
    pkgs.git
    pkgs.git-annex
  ];

  # ssh remote, so no daemon and no port. The Macs reach it as
  # gapul@homeserver:/srv/annex over the tailnet, like every other path here.
  systemd.tmpfiles.rules = [
    "d /srv/annex 0755 gapul users -"
  ];

  # Not in restic. The point of an annex is that every file exists in numcopies
  # places by construction, and `git annex fsck --from` is the check that says so
  # — a restic snapshot of the same bytes would double the storage to answer a
  # question git-annex already answers. The git history (the filenames, which are
  # the part that is hard to reproduce) lives in /srv/annex/.git and is small;
  # it is on the Macs too, because that is what a clone is.
}
