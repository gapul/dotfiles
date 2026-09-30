# Shell history sync server (atuin). tailnet only.
#
# The endpoint for sharing command history across machines. It uses atuin's own sync rather than
# file sync. The reason is conflicts: putting the history SQLite on Syncthing means both machines
# write the same file, which always conflicts. atuin is designed as per-record append-only, and
# it also encrypts client-side before syncing (the server cannot read the contents).
#
# So "self-hosting" means something slightly different here than for other services. Privacy is
# already covered by encryption, so the reasons to self-host are availability and not depending
# on someone else's server.
#
# database.createLocally defaults to true, so this box gets its first native PostgreSQL
# (all previous postgres instances were containers). It connects over a UNIX socket, so no port
# is opened.
#
# openRegistration stays false. Only when creating an account, set it to true temporarily, run
# `atuin register`, and revert it afterwards. Leaving it open lets anyone in the tailnet create
# an account.
{
  services.atuin = {
    enable = true;
    # Caddy calls it from the same box, so loopback is enough.
    host = "127.0.0.1";
    port = 8888;
    openRegistration = false;
  };
}
