{
  config,
  pkgs,
  lib,
  ...
}:
# Periodic maintenance launchd agents (macOS only).
# Approach: update tasks only "check + notify", never auto-apply (darwin switch requires sudo+brew trust = just rebuild,
#   the nh dirty tree cache issue, and the Determinate runtime needs a manual sudo upgrade, so unattended apply is risky.
#   Details: [[project_homebrew_trust_sudo]] [[project_nh_dirty_tree_cache]]). Only GC/cleanup are auto-applied (safe).
let
  home = config.home.homeDirectory;
  flakeDir = "${home}/.dotfiles/nix";
  logDir = "${home}/Library/Logs";

  # PATH that can resolve nix / brew / ghq even outside an interactive shell
  toolPath = lib.concatStringsSep ":" [
    "/nix/var/nix/profiles/default/bin"
    "${home}/.nix-profile/bin"
    "${home}/.local/state/nix/profile/bin"
    "/run/current-system/sw/bin"
    "/opt/homebrew/bin"
    "/usr/bin"
    "/bin"
  ];

  prelude = log: ''
    set -uo pipefail
    export PATH=${toolPath}:${
      lib.makeBinPath [
        pkgs.git
        pkgs.jq
        pkgs.coreutils
      ]
    }:$PATH
    lock=${home}/.local/state/dotfiles-maintenance.lock
    mkdir -p ${home}/.local/state
    if ! mkdir "$lock" 2>/dev/null; then
      echo "SKIP: another dotfiles maintenance task is running"
      exit 0
    fi
    trap 'rmdir "$lock" 2>/dev/null || true' EXIT
    notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true; }
    mkdir -p ${logDir}
    exec >>"${logDir}/${log}" 2>&1
    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') ${log} ===================="
  '';

  # (1) Update check (weekly, non-destructive, notify only)
  updateCheckScript = pkgs.writeShellScript "nix-update-check" ''
    ${prelude "maintenance-update.log"}
    msgs=""

    # flake inputs: update a temporary copy and diff the lock (don't touch the real repo)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"; rmdir "$lock" 2>/dev/null || true' EXIT
    cp ${flakeDir}/flake.nix ${flakeDir}/flake.lock "$tmp"/ 2>/dev/null || true
    ( cd "$tmp" && git init -q && git add -A && nix flake update >/dev/null 2>&1 ) || true
    changed=$(jq -r --slurpfile new "$tmp/flake.lock" '
      .nodes as $old | $new[0].nodes as $n
      | [ $n | keys[] | select($old[.].locked.rev != $n[.].locked.rev) ] | join(", ")
    ' ${flakeDir}/flake.lock 2>/dev/null)
    rm -rf "$tmp"
    trap 'rmdir "$lock" 2>/dev/null || true' EXIT
    [ -n "$changed" ] && { echo "flake 更新可能: $changed"; msgs="flake: $changed"; }

    # brew / mas
    bo=$(brew outdated --greedy 2>/dev/null | wc -l | tr -d ' ')
    mo=$(mas outdated 2>/dev/null | wc -l | tr -d ' ')
    [ "$bo" != "0" ] && msgs="$msgs / brew: $bo"
    [ "$mo" != "0" ] && msgs="$msgs / mas: $mo"
    echo "brew outdated: $bo, mas outdated: $mo"

    if [ -n "$msgs" ]; then
      notify "⬆️ 更新あり (just upgrade)" "$msgs"
    else
      echo "全て最新"
    fi
  '';

  # (2) nix store GC (monthly, safe auto-apply)
  nixGcScript = pkgs.writeShellScript "nix-gc" ''
    ${prelude "maintenance-gc.log"}
    before=$(df -h /nix 2>/dev/null | awk 'NR==2{print $4}')
    nix-collect-garbage --delete-older-than 30d 2>&1 || true
    after=$(df -h /nix 2>/dev/null | awk 'NR==2{print $4}')
    echo "free /nix: $before -> $after"
  '';

  # (3) Detect unpushed repos (weekly, notify only). Prevents recurrence of local-only data
  unpushedScript = pkgs.writeShellScript "git-unpushed-check" ''
    ${prelude "maintenance-unpushed.log"}
    root=${home}/Developer
    count=0
    while IFS= read -r g; do
      r=$(dirname "$g")
      name=$(basename "$r")
      [ -z "$(git -C "$r" remote 2>/dev/null)" ] && { echo "NO-REMOTE: $name"; count=$((count+1)); continue; }
      u=$(git -C "$r" log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' ')
      d=$(git -C "$r" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
      if [ "$u" != "0" ] || [ "$d" != "0" ]; then
        echo "PENDING: $name (unpushed:$u dirty:$d)"
        count=$((count+1))
      fi
    done < <(find "$root" -type d -name .git -maxdepth 6 2>/dev/null)
    echo "要対応リポ数: $count"
    [ "$count" != "0" ] && notify "📦 未push/未コミットのリポ" "$count 件。詳細はログ参照"
  '';

  # (4) brew cleanup (monthly, safe auto-apply)
  brewCleanupScript = pkgs.writeShellScript "brew-cleanup" ''
    ${prelude "maintenance-brew.log"}
    brew cleanup --prune=all 2>&1 | tail -20 || true
  '';

  # (5) Daily git push of the Obsidian vault (history + GitHub backup).
  #   Live cross-device sync is handled by LiveSync (CouchDB), so daily git is enough.
  #   obsidian-git's auto-commit is expected to be OFF, consolidating ownership in this agent.
  vaultGitPushScript = pkgs.writeShellScript "obsidian-vault-push" ''
    ${prelude "obsidian-vault.log"}
    vault=${home}/Documents/notes
    branch=main

    [ -d "$vault/.git" ] || { echo "SKIP: $vault は git リポジトリではない"; exit 0; }
    [ -n "$(git -C "$vault" remote 2>/dev/null)" ] || { echo "SKIP: remote 未設定"; exit 0; }

    # Point explicitly at the Bitwarden SSH agent (so keys are reachable even in an unattended launchd session).
    # Requires Bitwarden Desktop to be running and unlocked.
    [ -S "${home}/.bitwarden-ssh-agent.sock" ] && export SSH_AUTH_SOCK="${home}/.bitwarden-ssh-agent.sock"
    export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15"

    git -C "$vault" add -A
    if git -C "$vault" diff --cached --quiet; then
      echo "変更なし (commit スキップ)"
    else
      git -C "$vault" commit -m "vault backup: $(date '+%Y-%m-%d %H:%M:%S')" && echo "commit 作成"
    fi

    # Pull in changes from other machines before pushing (rebase on conflict; flake.lock etc. are out of scope)
    git -C "$vault" pull --rebase --autostash origin "$branch" || echo "WARN: pull --rebase 失敗 (続行)"

    if git -C "$vault" push origin "$branch"; then
      echo "push 成功"
    else
      echo "ERROR: push 失敗 (Bitwarden ロック / 認証不可の可能性)"
      notify "📝 vault git push 失敗" "Bitwarden ロック中か認証不可。ログ確認"
      exit 1
    fi
  '';

  agent = program: schedule: {
    enable = true;
    config = {
      ProgramArguments = [ program ];
      StartCalendarInterval = schedule;
      RunAtLoad = false;
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 10;
    };
  };
in
{
  launchd.agents = {
    # Weekly (Mon) 12:00 update check
    nix-update-check = agent "${updateCheckScript}" [
      {
        Weekday = 1;
        Hour = 12;
        Minute = 0;
      }
    ];
    # Monthly (1st) 12:30 nix GC
    nix-gc = agent "${nixGcScript}" [
      {
        Day = 1;
        Hour = 12;
        Minute = 30;
      }
    ];
    # Weekly (Mon) 12:15 detect unpushed repos
    git-unpushed-check = agent "${unpushedScript}" [
      {
        Weekday = 1;
        Hour = 12;
        Minute = 15;
      }
    ];
    # Monthly (1st) 12:45 brew cleanup
    brew-cleanup = agent "${brewCleanupScript}" [
      {
        Day = 1;
        Hour = 12;
        Minute = 45;
      }
    ];
    # Daily 13:30 git push the Obsidian vault (after restic at 13:00)
    obsidian-vault-push = agent "${vaultGitPushScript}" [
      {
        Hour = 13;
        Minute = 30;
      }
    ];
  };
}
