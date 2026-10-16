# AI agents component (ECS: profile). Codex/Claude config, themes, environment variables.
{
  config,
  pkgs,
  ...
}:
let
  rosePineTmThemes = import ../../lib/rose-pine-tm-theme.nix { inherit pkgs; };
  agentStateRepo = "${config.home.homeDirectory}/Developer/github.com/gapul/ai-agent-state";
in
{
  home.sessionVariables = {
    CLAUDE_CONFIG_DIR = "${config.home.homeDirectory}/.config/claude";
    CODEX_HOME = "${config.xdg.dataHome}/codex";
    CODEX_SQLITE_HOME = "${config.xdg.stateHome}/codex/sqlite";
  };

  # Codex: upstream defaults to ~/.codex, but CODEX_HOME moves it under XDG data.
  # auth/history/skills/plugins go to CODEX_HOME, SQLite is separated into CODEX_SQLITE_HOME.
  # Use an out-of-store symlink so settings updated from the TUI are reflected back into the repo.
  xdg.dataFile."codex/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${agentStateRepo}/codex/config.toml";
  xdg.dataFile."codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${agentStateRepo}/AGENTS.md";
  # Bitwarden Agent Access: agents may only `aac run` (credential goes into the child's env).
  # `aac connect` can print the credential to stdout, and `aac listen` is the human approval
  # side. Execpolicy rules hold even under approval_policy = "never"; Claude Code gets the same
  # pair through permissions.deny (configs/cli/claude/settings.remote.json).
  xdg.dataFile."codex/rules/aac.rules".text = ''
    prefix_rule(
        pattern = ["aac", ["connect", "listen"]],
        decision = "forbidden",
        justification = "agents only get `aac run`; connect can print credentials and listen is the human approval side",
    )
  '';
  # `aac listen` has no notification of its own, so a pending approval in its tmux pane goes
  # unseen. This PreToolUse hook pushes one through ntfy (~/.config/ntfy/{url,token}, macmini)
  # when an agent starts `aac run`, falling back to agent-notify elsewhere. It never blocks the
  # call. Wired up in the Claude settings (hooks.PreToolUse).
  home.file.".local/bin/aac-approval-notify".source = pkgs.writeShellScript "aac-approval-notify" ''
    set -u
    cmd=$(${pkgs.jq}/bin/jq -r '.tool_input.command // "" | if type == "array" then join(" ") else . end' 2>/dev/null) || exit 0
    [[ $cmd =~ (^|[[:space:]\;\&\|\(])aac[[:space:]]+run([[:space:]]|$) ]] || exit 0
    target=$(printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -oE -- '--(domain|id)[= ][^ ]+' | head -n1 | ${pkgs.gnused}/bin/sed -E 's/^--(domain|id)[= ]//')
    child=""
    [[ $cmd == *" -- "* ]] && child=''${cmd#* -- }
    message="''${target:-?} → ''${child:-?}"
    title="aac: approval pending"
    ntfy="$HOME/.config/ntfy"
    if [[ -r $ntfy/url && -r $ntfy/token ]]; then
      url=$(<"$ntfy/url") token=$(<"$ntfy/token")
      body=$(${pkgs.jq}/bin/jq -n --arg topic "''${url##*/}" --arg title "$title" --arg message "$message" \
        '{topic: $topic, title: $title, message: $message, tags: ["key"], priority: 4}')
      # Detached so the agent's command starts (and reaches `aac listen`) without waiting on the push.
      (${pkgs.curl}/bin/curl -fsS -m 10 -H "Authorization: Bearer $token" -d "$body" "''${url%/*}" >/dev/null 2>&1 &)
    elif [[ -x $HOME/.local/bin/agent-notify ]]; then
      "$HOME/.local/bin/agent-notify" "$title" "$message" </dev/null >/dev/null 2>&1 || true
    fi
    exit 0
  '';
  xdg.dataFile."codex/themes/rose-pine.tmTheme".source = "${rosePineTmThemes}/dist/rose-pine.tmTheme";
  xdg.dataFile."codex/themes/rose-pine-dawn.tmTheme".source =
    "${rosePineTmThemes}/dist/rose-pine-dawn.tmTheme";

  # Keep the cross-agent instructions identical on every host, including the headless macmini.
  # CLAUDE.md is a small Claude-specific adapter that imports the canonical AGENTS.md beside it.
  xdg.configFile."claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${agentStateRepo}/claude/CLAUDE.md";
  xdg.configFile."claude/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${agentStateRepo}/AGENTS.md";
}
