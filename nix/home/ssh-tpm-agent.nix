{ lib, ... }:
{
  # TPM-sealed SSH key for the laptop (nixos-laptop only).
  #
  # This is the Linux counterpart of the Mac's Secure Enclave key: ssh-tpm-keygen creates the key
  # inside the TPM and it cannot be extracted, so losing the machine does not leak a usable key.
  # It matters most here — the laptop leaves the house, and it is the client that carries the
  # longest-lived SSH certificate (it cannot renew its own; only the Mac can sign).
  #
  # Not on WSL despite sharing home/linux.nix: no TPM there.
  # Not a substitute for the LUKS TPM+PIN slot in hosts/nixos-laptop.nix — different key, different
  # purpose. Note fprintd (sudo / hyprlock) does not gate this: on Linux a fingerprint authenticates
  # a session via PAM, it is not a policy the TPM can attach to a key. The available binding is a
  # PIN on the key itself, which is what ssh-tpm-keygen offers.
  services.ssh-tpm-agent.enable = true;

  # home-manager's sshAuthSock.initialization only defines bash / fish / nushell (see
  # modules/misc/ssh-auth-sock.nix), so a zsh login gets no SSH_AUTH_SOCK and ssh would fall
  # through to whatever ~/.ssh/config names. Export it here instead of patching upstream.
  programs.zsh.initContent = lib.mkOrder 550 ''
    export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR:-/run/user/$UID}/ssh-tpm-agent.sock"
  '';
}
