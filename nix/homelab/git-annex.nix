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
# On the licensing constraint, which this module used to get wrong. The first version
# excluded commercial Japanese fonts from this remote:
#
#   git annex wanted homeserver 'exclude=fonts/commercial/*'
#
# on the reading that their EULAs forbid placing them "on a server". That was guarding the
# wrong thing. What those clauses are aimed at is *serving* — one licence reaching many
# machines or many people — and what they actually count is the number of devices the font is
# installed and used on. Moving bytes between machines that are all mine is not redistribution;
# installing on more machines than the licence allows is, and no storage rule can prevent that.
#
# This host is also not a server in the sense the clause imagines. It is a desktop that happens
# to stay powered on, reachable only over the tailnet, and the annex sits behind ssh with no
# daemon and no port. Nobody else can reach it.
#
# Meanwhile the exclusion had a cost that was clearly not intended: excluded files existed in
# exactly one place, the Mac. The annex is deliberately outside restic (see below), so the
# commercial fonts — the ones that cannot be re-downloaded — were the only assets here with no
# second copy at all. The rule inverted its own purpose.
#
# So: everything goes to this remote. The constraint that remains is a usage one, not a storage
# one — keep installs within what each licence allows — and it lives with the person, not in a
# preferred content expression.
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
