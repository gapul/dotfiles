{
  config,
  pkgs,
  lib,
  ...
}:
# 定期メンテナンス系の launchd agent (macOS 専用)。
# 方針: 更新系は「チェック + 通知」のみで自動適用しない (darwin switch は sudo+brew trust=just rebuild
#   必須、nh dirty tree キャッシュ問題、Determinate runtime は手動 sudo upgrade のため無人適用は危険。
#   詳細: [[project_homebrew_trust_sudo]] [[project_nh_dirty_tree_cache]])。GC/cleanup のみ自動適用 (安全)。
let
  home = config.home.homeDirectory;
  flakeDir = "${home}/.dotfiles/nix";
  logDir = "${home}/Library/Logs";

  # 対話シェル外でも nix / brew / ghq を解決できる PATH
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
    notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true; }
    mkdir -p ${logDir}
    exec >>"${logDir}/${log}" 2>&1
    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') ${log} ===================="
  '';

  # ① 更新チェック (週次・非破壊・通知のみ)
  updateCheckScript = pkgs.writeShellScript "nix-update-check" ''
    ${prelude "maintenance-update.log"}
    msgs=""

    # flake inputs: 一時コピーで update し lock 差分を見る (実リポは触らない)
    tmp=$(mktemp -d)
    cp ${flakeDir}/flake.nix ${flakeDir}/flake.lock "$tmp"/ 2>/dev/null || true
    ( cd "$tmp" && git init -q && git add -A && nix flake update >/dev/null 2>&1 ) || true
    changed=$(jq -r --slurpfile new "$tmp/flake.lock" '
      .nodes as $old | $new[0].nodes as $n
      | [ $n | keys[] | select($old[.].locked.rev != $n[.].locked.rev) ] | join(", ")
    ' ${flakeDir}/flake.lock 2>/dev/null)
    rm -rf "$tmp"
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

  # ② nix store GC (月次・安全な自動適用)
  nixGcScript = pkgs.writeShellScript "nix-gc" ''
    ${prelude "maintenance-gc.log"}
    before=$(df -h /nix 2>/dev/null | awk 'NR==2{print $4}')
    nix-collect-garbage --delete-older-than 30d 2>&1 || true
    after=$(df -h /nix 2>/dev/null | awk 'NR==2{print $4}')
    echo "free /nix: $before -> $after"
  '';

  # ③ 未push リポ検知 (週次・通知のみ)。ローカルのみデータの再発防止
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

  # ④ brew cleanup (月次・安全な自動適用)
  brewCleanupScript = pkgs.writeShellScript "brew-cleanup" ''
    ${prelude "maintenance-brew.log"}
    brew cleanup --prune=all 2>&1 | tail -20 || true
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
    # 週次 (月) 12:00 更新チェック
    nix-update-check = agent "${updateCheckScript}" [
      {
        Weekday = 1;
        Hour = 12;
        Minute = 0;
      }
    ];
    # 月次 (1日) 12:30 nix GC
    nix-gc = agent "${nixGcScript}" [
      {
        Day = 1;
        Hour = 12;
        Minute = 30;
      }
    ];
    # 週次 (月) 12:15 未push リポ検知
    git-unpushed-check = agent "${unpushedScript}" [
      {
        Weekday = 1;
        Hour = 12;
        Minute = 15;
      }
    ];
    # 月次 (1日) 12:45 brew cleanup
    brew-cleanup = agent "${brewCleanupScript}" [
      {
        Day = 1;
        Hour = 12;
        Minute = 45;
      }
    ];
  };
}
