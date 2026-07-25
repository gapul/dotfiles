{
  lib,
  writeShellApplication,
  gh,
  git,
  git-wt,
  jq,
}:
writeShellApplication {
  name = "git-wtpr";
  runtimeInputs = [
    gh
    git
    git-wt
    jq
  ];
  text = ''
    usage() {
      echo "usage: git wtpr <number|url> [git-wt options...]" >&2
      exit 2
    }

    [ "$#" -gt 0 ] || usage
    selector="$1"
    shift

    git rev-parse --git-dir >/dev/null 2>&1 || {
      echo "git-wtpr: not inside a Git repository" >&2
      exit 1
    }

    pr_json="$(gh pr view "$selector" --json number,headRefName,title,url)"
    number="$(jq -r .number <<<"$pr_json")"
    branch="$(jq -r .headRefName <<<"$pr_json")"
    title="$(jq -r .title <<<"$pr_json")"
    pr_repo="$(jq -r '.url | capture("github.com/(?<repo>[^/]+/[^/]+)/pull/").repo' <<<"$pr_json")"
    current_repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

    if [ "$pr_repo" != "$current_repo" ]; then
      echo "git-wtpr: PR belongs to $pr_repo, current repository is $current_repo" >&2
      exit 1
    fi

    case "$branch" in
      main|master) branch="pr-$number" ;;
    esac

    if git remote get-url origin >/dev/null 2>&1; then
      remote=origin
    else
      remote="$(git remote | head -n 1)"
    fi
    [ -n "$remote" ] || {
      echo "git-wtpr: no Git remote found" >&2
      exit 1
    }

    echo "git-wtpr: PR #$number — $title" >&2
    git fetch "$remote" "pull/$number/head"

    if git show-ref --verify --quiet "refs/heads/$branch" ||
       git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
      exec git wt --nocd "$@" "$branch"
    else
      exec git wt --nocd "$@" "$branch" FETCH_HEAD
    fi
  '';
  meta = {
    description = "Open a GitHub pull request in a git-wt worktree";
    license = lib.licenses.mit;
    mainProgram = "git-wtpr";
    platforms = lib.platforms.unix;
  };
}
