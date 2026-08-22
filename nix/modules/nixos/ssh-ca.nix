_: {
  # Trust the user CA so this host stops needing per-key authorized_keys edits.
  #
  # The CA private key lives in the MacBook's Secure Enclave with `protection = "bio"`, so a
  # certificate can only be minted while a human is physically there to touch the sensor. It is an
  # sk-ecdsa key: nix-secure-enclave-key hands the identity to macOS' CryptoTokenKit provider, which
  # OpenSSH sees as a FIDO authenticator, so `ssh-keygen -s ... -w /usr/lib/ssh-keychain.dylib`
  # signs through it. See `just ssh-cert`.
  #
  # There is deliberately no second CA. A backup CA would sit in TrustedUserCAKeys permanently —
  # standing authority to mint a certificate for any principal — while all it needs to buy is the
  # ability to get back in if the MacBook dies. A break-glass public key in authorized_keys does
  # that with login rights only, so that is what recovery uses (see docs/SSH_CA.md).
  #
  # Publishing the CA *public* key in a public repo is fine: it is what every trusting host has to
  # hold anyway, and it grants nothing on its own.
  environment.etc."ssh/gapul-user-ca.pub".source = ../../keys/ssh-user-ca.pub;

  services.openssh.settings.TrustedUserCAKeys = "/etc/ssh/gapul-user-ca.pub";

  # No AuthorizedPrincipalsFile: with a trusted CA, sshd accepts a user certificate whose principal
  # list contains the login name. `just ssh-cert` signs with -n for exactly that name, so adding a
  # machine means signing a certificate, not touching this host.
}
