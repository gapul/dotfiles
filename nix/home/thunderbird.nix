{ config, ... }:
# Thunderbird's mail accounts on nixos-laptop: the same two that aerc has (lib/aerc-accounts.nix
# has the reasoning for Gmail through Stalwart and gapul.net straight to Sakura).
#
# Not programs.thunderbird: home-manager writes the profile's user.js into the store, and the
# identities here carry pii/* addresses that must stay out of it. So the profile is declared by
# hand and user.js is a sops template, rendered at activation like aerc's accounts.conf.
# user.js is reapplied on every start, so the account list below wins over edits made in the UI.
#
# Passwords are not here: Thunderbird has no pref or file for them. It asks once per server and
# keeps the answer in its own password manager. The values are the decrypted sops secrets
# (stalwart/gmail, sakura/mail_password), e.g. `wl-copy < ~/.config/sops-nix/secrets/stalwart/gmail`.
#
# Push is IMAP IDLE (use_idle, on by default), so new mail shows up as it arrives on both servers.
let
  profile = "default";
  placeholder = name: config.sops.placeholder.${name};

  # socketType 3 = SSL/TLS, authMethod 3 = normal password (prefs use the numeric enums).
  userJs = ''
    user_pref("mail.accountmanager.accounts", "account1,account2,account3");
    user_pref("mail.accountmanager.defaultaccount", "account1");
    user_pref("mail.accountmanager.localfoldersserver", "server3");
    user_pref("mail.smtpservers", "smtp1,smtp2");
    user_pref("mail.smtp.defaultserver", "smtp1");

    // Gmail, through the Stalwart mirror. No copy to Sent: Google files its own and the mirror
    // brings it back.
    user_pref("mail.account.account1.server", "server1");
    user_pref("mail.account.account1.identities", "id1");
    user_pref("mail.server.server1.type", "imap");
    user_pref("mail.server.server1.name", "Gmail");
    user_pref("mail.server.server1.hostname", "mail.gapul.net");
    user_pref("mail.server.server1.port", 993);
    user_pref("mail.server.server1.socketType", 3);
    user_pref("mail.server.server1.authMethod", 3);
    user_pref("mail.server.server1.userName", "gmail");
    user_pref("mail.server.server1.login_at_startup", true);
    user_pref("mail.server.server1.check_new_mail", true);
    user_pref("mail.identity.id1.valid", true);
    user_pref("mail.identity.id1.fullName", "${placeholder "pii/name"}");
    user_pref("mail.identity.id1.useremail", "${placeholder "pii/email_personal"}");
    user_pref("mail.identity.id1.smtpServer", "smtp1");
    user_pref("mail.identity.id1.fcc", false);
    user_pref("mail.smtpserver.smtp1.type", "smtp");
    user_pref("mail.smtpserver.smtp1.description", "Gmail (Stalwart)");
    user_pref("mail.smtpserver.smtp1.hostname", "mail.gapul.net");
    user_pref("mail.smtpserver.smtp1.port", 465);
    user_pref("mail.smtpserver.smtp1.try_ssl", 3);
    user_pref("mail.smtpserver.smtp1.authMethod", 3);
    user_pref("mail.smtpserver.smtp1.username", "gmail");

    // gapul.net, Sakura directly. Sakura keeps folders under INBOX with "." as the separator;
    // folder URIs always use "/".
    user_pref("mail.account.account2.server", "server2");
    user_pref("mail.account.account2.identities", "id2");
    user_pref("mail.server.server2.type", "imap");
    user_pref("mail.server.server2.name", "gapul.net");
    user_pref("mail.server.server2.hostname", "gapul.sakura.ne.jp");
    user_pref("mail.server.server2.port", 993);
    user_pref("mail.server.server2.socketType", 3);
    user_pref("mail.server.server2.authMethod", 3);
    user_pref("mail.server.server2.userName", "gapul@gapul.sakura.ne.jp");
    user_pref("mail.server.server2.login_at_startup", true);
    user_pref("mail.server.server2.check_new_mail", true);
    user_pref("mail.identity.id2.valid", true);
    user_pref("mail.identity.id2.fullName", "${placeholder "pii/name"}");
    user_pref("mail.identity.id2.useremail", "gapul@gapul.net");
    user_pref("mail.identity.id2.smtpServer", "smtp2");
    user_pref("mail.identity.id2.fcc", true);
    user_pref("mail.identity.id2.fcc_folder_picker_mode", "1");
    user_pref("mail.identity.id2.fcc_folder", "imap://gapul%40gapul.sakura.ne.jp@gapul.sakura.ne.jp/INBOX/Sent");
    user_pref("mail.identity.id2.drafts_folder_picker_mode", "1");
    user_pref("mail.identity.id2.draft_folder", "imap://gapul%40gapul.sakura.ne.jp@gapul.sakura.ne.jp/INBOX/Draft");
    user_pref("mail.smtpserver.smtp2.type", "smtp");
    user_pref("mail.smtpserver.smtp2.description", "gapul.net (Sakura)");
    user_pref("mail.smtpserver.smtp2.hostname", "gapul.sakura.ne.jp");
    user_pref("mail.smtpserver.smtp2.port", 465);
    user_pref("mail.smtpserver.smtp2.try_ssl", 3);
    user_pref("mail.smtpserver.smtp2.authMethod", 3);
    user_pref("mail.smtpserver.smtp2.username", "gapul@gapul.sakura.ne.jp");

    // Local Folders. Declared so the account list above is complete; otherwise Thunderbird adds
    // it to the list in prefs.js on every start, only for user.js to take it away again.
    user_pref("mail.account.account3.server", "server3");
    user_pref("mail.server.server3.type", "none");
    user_pref("mail.server.server3.name", "Local Folders");
    user_pref("mail.server.server3.hostname", "Local Folders");
    user_pref("mail.server.server3.userName", "nobody");
  '';
in
{
  # Same shape home-manager's own module writes. A single Default=1 profile is claimed by the
  # install on first start, so no installs.ini entry is needed.
  home.file.".thunderbird/profiles.ini".text = ''
    [General]
    StartWithLastProfile=1
    Version=2

    [Profile0]
    Name=${profile}
    IsRelative=1
    Path=${profile}
    Default=1
  '';

  sops.templates."thunderbird-user.js" = {
    path = "${config.home.homeDirectory}/.thunderbird/${profile}/user.js";
    content = userJs;
  };
}
