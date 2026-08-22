_: {
  # The darwin half of modules/nixos/ssh-ca.nix: trust the same user CA on the Macs that get
  # SSH'd into. macOS ships its own sshd rather than a nix-darwin-managed one, but its
  # /etc/ssh/sshd_config ends with `Include /etc/ssh/sshd_config.d/*`, so a drop-in is enough
  # and nothing has to be patched in place.
  #
  # The CA private key lives in this machine's own Secure Enclave when the host is the MacBook.
  # That is fine: sshd only ever reads the public half, and trusting the CA you sign with is the
  # normal shape — the certificate still has to be minted with Touch ID first.
  environment.etc."ssh/gapul-user-ca.pub".source = ../../keys/ssh-user-ca.pub;

  environment.etc."ssh/sshd_config.d/100-gapul-user-ca.conf".text = ''
    TrustedUserCAKeys /etc/ssh/gapul-user-ca.pub
  '';
}
