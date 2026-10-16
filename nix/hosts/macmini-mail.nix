# aerc on macmini, with the same accounts as the workstations (lib/aerc-accounts.nix).
#
# The workstations render accounts.conf through home-manager's sops with the human age key. This
# host declares its secrets on the system side instead (see the sops block in macmini.nix), which
# decrypts with the SSH host key during activation, so the file is rendered here as root and
# handed to the login user. The password files are read by aerc's cred-cmd at connect time, so
# they belong to the user as well.
{
  config,
  pkgs,
  user,
  ...
}:
let
  forUser = {
    owner = user.username;
    mode = "0400";
  };
in
{
  sops.secrets = {
    "stalwart/gmail" = forUser // {
      sopsFile = ../../secrets/mail.yaml;
    };
    "sakura/mail_password" = forUser;
    # Only spliced into the template, which root renders; nobody reads these files directly.
    "pii/name" = { };
    "pii/email_personal" = { };
  };

  sops.templates."aerc-accounts.conf" = forUser // {
    path = "/Users/${user.username}/.config/aerc/accounts.conf";
    content = import ../lib/aerc-accounts.nix {
      placeholder = name: config.sops.placeholder.${name};
      secretPath = name: config.sops.secrets.${name}.path;
    };
  };

  environment.systemPackages = [ pkgs.aerc ];
}
