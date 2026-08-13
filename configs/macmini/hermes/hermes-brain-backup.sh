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


# 妹用(まなび)。HOME を分けた2本目の gateway と、サンドボックス内の学習記録。
# どちらも消えると作り直せないので同じ repo に入れる。
IMOUTO=/Users/hermes/imouto-home/.hermes
if [ -d "$IMOUTO" ]; then
  mkdir -p "$REPO/imouto"
  rsync -a "$IMOUTO/SOUL.md" "$IMOUTO/config.yaml" "$REPO/imouto/" 2>/dev/null || true
  # 継ぎ手(claude-acp)は自作で再作成できないので一緒に退避する。
  rsync -a /Users/hermes/.local/bin/claude-acp "$REPO/imouto/" 2>/dev/null || true
  for d in memories skills cron; do
    [ -d "$IMOUTO/$d" ] && rsync -a --delete "$IMOUTO/$d/" "$REPO/imouto/$d/"
  done
fi

# 学習記録(試験結果/課題/進捗/勉強時間/暗記カード)はサンドボックス側にある
mkdir -p "$REPO/study"
ssh -o BatchMode=yes -i /Users/hermes/.ssh/sandbox_ed25519 hsandbox@localhost \
  "tar cf - -C ~ study --exclude='.gcal_token.json' --exclude='.dashboard_auth' --exclude='.gcal_client.json'" \
  2>/dev/null | tar xf - -C "$REPO/study" --strip-components=1 || true

# 秘密は平文では置かないが、飛んだときに手で入れ直すのも困る。
# 公開鍵だけで暗号化できるので、暗号文だけ repo に入れておく。
# 復号は age の秘密鍵を持っている母艦側で:  sops -d secrets/imouto.env.enc
SOPS=/etc/profiles/per-user/gapul/bin/sops
AGE_RECIPIENTS=age1crkk4dtd824qu3h5q24vnm4pmrjymzkelt60qnyzwcje74gncudqjr693n,age1wkurr3ldjxslj4t3sa47lpslc9flpyznruxmgtqejar9ews59gqqvmkz55
if [ -x "$SOPS" ]; then
  mkdir -p "$REPO/secrets"
  for pair in "imouto:/Users/hermes/imouto-home/.hermes/.env" "main:/Users/hermes/.hermes/.env"; do
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
if ! git diff --cached --quiet; then
  git -c user.name="hermes" -c user.email="hermes@macmini.gapul.net" \
    commit -m "auto backup $(date +%Y-%m-%d_%H%M)"
  git push origin main
  echo "$(date '+%F %T') pushed"
else
  echo "$(date '+%F %T') no changes"
fi
