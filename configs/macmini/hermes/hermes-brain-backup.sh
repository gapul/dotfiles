#!/bin/bash
# Hermes brain バックアップ (hermes ユーザーで毎晩 03:30 実行)
# 記憶・設定・スキルなど再構築できない資産だけを GitHub private repo に push する。
# 機密 (.env / auth.json / sessions / DB) は含めない。
set -euo pipefail

export HOME=/Users/hermes
export PATH=/opt/homebrew/bin:/usr/bin:/bin
SRC=/Users/hermes/.hermes
REPO=/Users/hermes/hermes-brain

cd "$REPO" || exit 1

rsync -a "$SRC/SOUL.md" "$SRC/config.yaml" "$REPO/"
for d in memories skills hooks cron; do
  [ -d "$SRC/$d" ] && rsync -a --delete "$SRC/$d/" "$REPO/$d/"
done


# まなび。HOME を分けた2本目の gateway と、サンドボックス内の学習記録。
# どちらも消えると作り直せないので同じ repo に入れる。
MANABI=/Users/hermes/manabi-home/.hermes
if [ -d "$MANABI" ]; then
  mkdir -p "$REPO/manabi"
  rsync -a "$MANABI/SOUL.md" "$MANABI/config.yaml" "$REPO/manabi/" 2>/dev/null || true
  # 継ぎ手(claude-acp)はここでは退避しない。gapul/claude-acp が正で、この機械には
  # dotfiles の activation が store から敷いている。
  for d in memories skills cron; do
    [ -d "$MANABI/$d" ] && rsync -a --delete "$MANABI/$d/" "$REPO/manabi/$d/"
  done
fi

# 学習記録(試験結果/課題/進捗/勉強時間/暗記カード)はサンドボックス側にある
# 生成物(画像/PDF)と向こうの .git は持ってこない。前者は作り直せるし、後者は
# 中身がそのままファイルとして積まれて履歴が膨らむ。学習記録の履歴は
# サンドボックス側の git にある。
# 展開してから差し替えるのは、向こうで消えたファイルをこちらにも反映するため
# (tar は上書きするだけなので、そのままだと消したものが残り続ける)。
study_tmp=$(mktemp -d)
# --exclude は操作対象より前に置く。後ろに書くと「has no effect」と言われて
# 素通りする(この書き方だったせいで .dashboard_auth と .gcal_client.json が
# 8/10 から repo に入っていた)。
if ssh -o BatchMode=yes -i /Users/hermes/.ssh/sandbox_ed25519 hsandbox@localhost \
  "tar cf - --exclude='.git' --exclude='*.png' --exclude='*.pdf' \
   --exclude='.gcal_token.json' --exclude='.dashboard_auth' --exclude='.gcal_client.json' \
   -C ~ study" \
  2>/dev/null | tar xf - -C "$study_tmp" --strip-components=1; then
  rm -rf "$REPO/study"
  mv "$study_tmp" "$REPO/study"

  # 学習記録の git 履歴はサンドボックスのディスクにしかない。丸ごとは重いので
  # bundle 1ファイルで持ち出す(復元: git clone study.bundle)。
  if ssh -o BatchMode=yes -i /Users/hermes/.ssh/sandbox_ed25519 hsandbox@localhost \
    "cd ~/study && git bundle create /tmp/.study.bundle --all -q && cat /tmp/.study.bundle && rm -f /tmp/.study.bundle" \
    > "$REPO/study.bundle.new" 2>/dev/null && [ -s "$REPO/study.bundle.new" ]; then
    mv "$REPO/study.bundle.new" "$REPO/study.bundle"
  else
    rm -f "$REPO/study.bundle.new"
  fi
else
  rm -rf "$study_tmp"
fi

# 秘密は平文では置かないが、飛んだときに手で入れ直すのも困る。
# 公開鍵だけで暗号化できるので、暗号文だけ repo に入れておく。
# 復号は age の秘密鍵を持っている母艦側で:  sops -d secrets/manabi.env.enc
SOPS=/etc/profiles/per-user/gapul/bin/sops
AGE_RECIPIENTS=age1crkk4dtd824qu3h5q24vnm4pmrjymzkelt60qnyzwcje74gncudqjr693n,age1wkurr3ldjxslj4t3sa47lpslc9flpyznruxmgtqejar9ews59gqqvmkz55
if [ -x "$SOPS" ]; then
  mkdir -p "$REPO/secrets"
  for pair in "manabi:/Users/hermes/manabi-home/.hermes/.env" "main:/Users/hermes/.hermes/.env"; do
    name=${pair%%:*}; file=${pair#*:}
    [ -f "$file" ] || continue
    # shellcheck disable=SC2015  # 失敗時は || 側で握り潰す意図どおり
    "$SOPS" --encrypt --age "$AGE_RECIPIENTS" \
      --input-type dotenv --output-type dotenv "$file" \
      > "$REPO/secrets/$name.env.enc.tmp" && \
      mv "$REPO/secrets/$name.env.enc.tmp" "$REPO/secrets/$name.env.enc" || \
      rm -f "$REPO/secrets/$name.env.enc.tmp"
  done
fi

git add -A

# 秘密と生成物はコミットしない。tar の除外がまた壊れても、ここで止まる。
# (除外の書き順ミスで資格情報が1か月コミットされ続けた事故の再発防止)
leaked=$(git diff --cached --name-only \
  | grep -E '(^|/)\.(dashboard_auth|gcal_client\.json|gcal_token\.json|studyplus[a-z_]*\.json)$|\.env$|\.png$|\.pdf$' || true)
if [ -n "$leaked" ]; then
  echo "$leaked" | while IFS= read -r f; do git reset -q -- "$f"; git rm -q --cached --ignore-unmatch "$f"; done
  echo "$(date '+%F %T') REFUSED to commit: $leaked" >&2
fi

if ! git diff --cached --quiet; then
  git -c user.name="hermes" -c user.email="hermes@macmini.gapul.net" \
    commit -m "auto backup $(date +%Y-%m-%d_%H%M)"
  git push origin main
  echo "$(date '+%F %T') pushed"
else
  echo "$(date '+%F %T') no changes"
fi
