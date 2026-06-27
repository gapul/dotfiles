#!/usr/bin/env bash
# 重要鍵を Bitwarden へ「1鍵=1アイテム」で登録する(冪等)。
#   - 専用フォルダ "Mac Keys (gapul)" にまとめる
#   - 各シークレットは hidden カスタムフィールド "key" に入れる(マスク+copyボタン)
#   - notes には用途/ファイルパス/復元方法を記載
#   - 同名アイテムがあれば更新、無ければ作成
#
# セキュリティ:
#   - 秘密値はコマンドライン引数に乗せない(jq へ --rawfile で 600 一時ファイル経由)
#   - マスターパスワードは bw unlock の対話入力のみ。実行後 再ロック。
#
# 使い方: bash ~/.dotfiles/scripts/backup-keys-to-bitwarden.sh
set -euo pipefail

FOLDER_NAME="Mac Keys (gapul)"
OLD_COMBINED="gapul Mac 重要鍵 (sops/restic/atuin/ssh)"  # 旧まとめノート(あれば削除)

# name|path|purpose(notes)
KEYS=(
  "SOPS age master key (gapul Mac)|$HOME/.config/sops/age/keys.txt|用途: sops 全シークレット(restic/rclone/ssh_config等)を復号するマスター鍵。これ1つで全部開く。復元: 値を ~/.config/sops/age/keys.txt へ配置し chmod 600。"
  "restic backup passphrase (gapul Mac)|$HOME/.config/sops-nix/secrets/restic_password|用途: restic 暗号リポジトリ(GDrive backup)のパスフレーズ。sops管理だが鍵自体は別保管必須。復元: restic 復号時に入力。"
  "atuin sync key (gapul Mac)|$HOME/.local/share/atuin/key|用途: atuin 履歴同期のE2E暗号鍵。他端末で履歴を復号するのに必須。復元: 値を ~/.local/share/atuin/key へ配置。"
)
# SSH 鍵は Bitwarden SSH agent 管理(ローカル無し)が通常。存在時のみ追加。
if [ -r "$HOME/.ssh/id_ed25519" ]; then
  KEYS+=("SSH private key id_ed25519 (gapul Mac)|$HOME/.ssh/id_ed25519|用途: SSH 認証/署名鍵。通常は Bitwarden SSH agent 管理。復元: ~/.ssh/id_ed25519 へ配置し chmod 600。")
fi

command -v bw >/dev/null || { echo "bw が見つかりません" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq が見つかりません" >&2; exit 1; }
for spec in "${KEYS[@]}"; do
  f=${spec#*|}; f=${f%%|*}
  [ -r "$f" ] || { echo "鍵が読めません: $f" >&2; exit 1; }
done

# --- アンロック ---
st=$(bw status | jq -r .status)
[ "$st" = "unauthenticated" ] && { echo "未ログインです。先に 'bw login'" >&2; exit 1; }
if [ "$st" != "unlocked" ] || [ -z "${BW_SESSION:-}" ]; then
  echo "Bitwarden をアンロックします(マスターパスワード入力)…"
  BW_SESSION=$(bw unlock --raw); export BW_SESSION
fi
bw sync >/dev/null 2>&1 || true

# --- フォルダを取得 or 作成 ---
folder_id=$(bw list folders --search "$FOLDER_NAME" \
  | jq -r --arg n "$FOLDER_NAME" '.[] | select(.name==$n) | .id' | head -1)
if [ -z "$folder_id" ]; then
  folder_id=$(bw get template folder | jq --arg n "$FOLDER_NAME" '.name=$n' \
    | bw encode | bw create folder | jq -r .id)
  echo "フォルダ作成: $FOLDER_NAME"
fi

# --- 旧まとめノートがあれば削除 ---
old_id=$(bw list items --search "$OLD_COMBINED" \
  | jq -r --arg n "$OLD_COMBINED" '.[] | select(.name==$n) | .id' | head -1)
[ -n "$old_id" ] && { bw delete item "$old_id" && echo "旧まとめノート削除: $OLD_COMBINED"; }

# --- 1鍵=1アイテムで upsert ---
tmp=$(mktemp); chmod 600 "$tmp"; trap 'rm -f "$tmp"' EXIT
for spec in "${KEYS[@]}"; do
  name=${spec%%|*}
  rest=${spec#*|}; path=${rest%%|*}; purpose=${rest#*|}
  cat "$path" > "$tmp"   # 秘密値は一時ファイルのみ

  existing_id=$(bw list items --search "$name" \
    | jq -r --arg n "$name" '.[] | select(.name==$n) | .id' | head -1)

  if [ -n "$existing_id" ]; then
    bw get item "$existing_id" \
      | jq --arg notes "$purpose" --rawfile key "$tmp" \
          '.notes=$notes | .fields=[{name:"key",value:$key,type:1}]' \
      | bw encode | bw edit item "$existing_id" >/dev/null
    echo "更新: $name"
  else
    bw get template item \
      | jq --arg name "$name" --arg fid "$folder_id" --arg notes "$purpose" --rawfile key "$tmp" \
          '.type=2 | .name=$name | .folderId=$fid | .notes=$notes
           | .secureNote={type:0} | .fields=[{name:"key",value:$key,type:1}]
           | .login=null | .card=null | .identity=null' \
      | bw encode | bw create item >/dev/null
    echo "作成: $name"
  fi
done

bw lock >/dev/null 2>&1 || true
echo "完了(Bitwarden 再ロック)。フォルダ \"$FOLDER_NAME\" に ${#KEYS[@]} 件。"
