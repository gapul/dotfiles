#!/usr/bin/env bash
# Hermes の状態を /Users/Shared/hermes-backups へ固める。
#
# Hermes は専用ユーザーで動いていて、そのホームは drwx------ なので gapul の restic からは
# 読めない。マイクラのワールドと同じ形にした: root の daemon がここで tar にして共有場所に置き、
# restic(5:00)はそれを拾うだけにする。restic に sudo を持たせるより、読める場所へ運ぶ方が安い。
#
# 入れるのは作り直せないものだけ。state.db は Discord の会話とその全文検索インデックス、
# .env 系は Discord トークンと移行の履歴。hermes-agent 本体と node と cache は
# 再インストールできるので入れない。
set -euo pipefail

src=/Users/hermes/.hermes
dst=/Users/Shared/hermes-backups
keep=14

[ -d "$src" ] || { echo "$(date '+%F %T') skip: $src が無い"; exit 0; }
/bin/mkdir -p "$dst"

stamp=$(/bin/date +%Y%m%d-%H%M)
out="$dst/hermes-$stamp.tar.gz"

# state.db は稼働中に書かれる。SQLite の online backup で一貫したコピーを取ってから固める。
tmp=$(/usr/bin/mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [ -f "$src/state.db" ]; then
  /usr/bin/sqlite3 "$src/state.db" ".backup '$tmp/state.db'"
fi
for f in "$src"/.env*; do
  [ -e "$f" ] && /bin/cp "$f" "$tmp/" || true
done
[ -d "$src/skills" ] && /bin/cp -R "$src/skills" "$tmp/" || true

/usr/bin/tar -czf "$out" -C "$tmp" .
/bin/chmod 644 "$out"
echo "$(date '+%F %T') ok: $out ($(/usr/bin/du -h "$out" | /usr/bin/cut -f1))"

# 世代を絞る。restic 側でも履歴は持つが、共有ディスクに積み続ける理由は無い。
/bin/ls -1t "$dst"/hermes-*.tar.gz 2>/dev/null | /usr/bin/tail -n +$((keep + 1)) | while IFS= read -r old; do
  /bin/rm -f "$old"
done
