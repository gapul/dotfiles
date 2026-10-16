# aerc's accounts.conf, shared by the workstations (home/secrets.nix, home-manager sops) and
# macmini (hosts/macmini.nix, system sops with the host key). Both render it as a sops template;
# they differ only in how a secret is referred to, so the caller passes those two functions in.
#
#   placeholder name → the sops placeholder for a value that is spliced into the file
#   secretPath name  → the path of a decrypted secret, read by a cred-cmd at connect time
#
# Passwords go through `cat <path>` rather than a placeholder so that a password containing
# shell or URL metacharacters (the Stalwart ones are base64 and have `/` and `+`) is never parsed.
#
# Gmail is read through the home Stalwart mirror, not Google: Google's app password stays on
# homeserver, and mail-push-gmail (homelab/mail.nix) copies new INBOX mail over as it arrives.
# Stalwart supports IDLE, so aerc sees it within seconds. mail.gapul.net is tailnet-only.
# No copy-to there: Stalwart relays through Google, which files its own copy in Sent, and the
# mirror brings that back as "Sent Items". Saving one here as well would leave two.
#
# gapul.net is Sakura's mailbox directly (it is not mirrored). Its login is an address, so the
# @ is percent-encoded in the URL. Sakura names its folders under INBOX with "." as the separator.
{ placeholder, secretPath }:
''
  [gmail]
  source = imaps://gmail@mail.gapul.net:993
  source-cred-cmd = cat ${secretPath "stalwart/gmail"}
  outgoing = smtps+plain://gmail@mail.gapul.net:465
  outgoing-cred-cmd = cat ${secretPath "stalwart/gmail"}
  from = ${placeholder "pii/name"} <${placeholder "pii/email_personal"}>
  default = INBOX

  [gapul.net]
  source = imaps://gapul%40gapul.sakura.ne.jp@gapul.sakura.ne.jp:993
  source-cred-cmd = cat ${secretPath "sakura/mail_password"}
  outgoing = smtps+plain://gapul%40gapul.sakura.ne.jp@gapul.sakura.ne.jp:465
  outgoing-cred-cmd = cat ${secretPath "sakura/mail_password"}
  from = ${placeholder "pii/name"} <gapul@gapul.net>
  default = INBOX
  copy-to = INBOX.Sent
  postpone = INBOX.Draft
''
