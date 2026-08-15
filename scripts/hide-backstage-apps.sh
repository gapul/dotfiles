#!/usr/bin/env bash
# macOS 26 の Applications ランチャー (と Spotlight のアプリ一覧) から、押しても意味のない
# 裏方アプリを引っ込める。
#
# ランチャーが並べているのは LaunchServices に登録されたバンドルで、LSUIElement も
# LSBackgroundOnly も効かない。ActivityWatch は LSBackgroundOnly が立っているのに並ぶし、
# Karabiner のドライバマネージャはファイル名がドット始まりでも並ぶ。名前で隠す手も
# 属性で隠す手もないので、登録そのものを外すしかない。
#
# 外すだけでファイルには触らない。Adobe のインストールディレクトリの中身を消すと
# Creative Cloud が黙って復元してくるが (実際に一度やられた)、登録を外す分には復元されない。
#
# ただしアプリを起動したり、Adobe が更新を入れたりすると登録し直される。そうしたら
# また実行する、という運用にしてある。常駐させるほどの頻度では戻ってこない。
set -euo pipefail

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x $lsregister ]] || {
	echo "error: lsregister が見つからない (macOS 専用)" >&2
	exit 1
}

# 実体を消してはいけない、しかしランチャーに並ぶ意味もないもの。
targets=(
	# Karabiner の仮想キーボードドライバの管理役。ドット始まりの隠しファイルなのに並ぶ
	"/Applications/.Karabiner-VirtualHIDDevice-Manager.app"

	# Creative Cloud まわりの裏方。ユーザーが開くのは Creative Cloud.app だけで、
	# あとは常駐・インストーラ・診断ツール
	"/Applications/Utilities/Adobe Creative Cloud Experience/CCXProcess/CCXProcess.app"
	"/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud Helper.app"
	"/Applications/Utilities/Adobe Creative Cloud/Diagnostics/Adobe Creative Cloud Diagnostics.app"
	"/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Desktop App.app"
	"/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Installer.app"
	"/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Uninstaller.app"
	"/Applications/Utilities/Adobe Sync/CoreSync/Core Sync.app"

	# Illustrator 同梱の AppleScript サンプル。スクリプト本体は残す
	"/Applications/Adobe Illustrator 2026/Scripting.localized/Sample Scripts.localized/AppleScript.localized/Calendar.localized/Make Calendar.app"
	"/Applications/Adobe Illustrator 2026/Scripting.localized/Sample Scripts.localized/AppleScript.localized/Contact Sheet Demo.localized/Contact Sheets.app"
	"/Applications/Adobe Illustrator 2026/Scripting.localized/Sample Scripts.localized/AppleScript.localized/Web Gallery.localized/Web Gallery.app"

	# After Effects のプレーナートラッカー。AE の中から開くもので、単体で起動しない
	"/Applications/Adobe After Effects 2026/Plug-ins/Effects/mochaAE/Resources/mochaui/Mocha AE.app"
)

# ダンプは 10 秒近くかかるうえ 100MB 近い。1 回だけ取って両方の判定に使い回す。
# `-dump | grep -q` を直に書くと、grep が先に抜けて lsregister が SIGPIPE で死に、
# pipefail のせいで「登録なし」と誤判定する。
dump=$("$lsregister" -dump 2>/dev/null || true)
registered_paths=$(printf '%s\n' "$dump" | sed -n 's/^path:  *\(.*\.app\)\( (0x[0-9a-f]*)\)\{0,1\}$/\1/p')

hidden=0
for app in "${targets[@]}"; do
	[[ -e $app ]] || continue
	if printf '%s\n' "$registered_paths" | grep -qxF "$app"; then
		"$lsregister" -u "$app" 2>/dev/null || true
		echo "hid  $app"
		hidden=$((hidden + 1))
	fi
done

# 実体が消えたのに登録だけ残っているゴースト。アプリの旧バージョンや、mac-app-util が
# 作って消えたトランポリンがここに溜まる。ランチャーには出ないが、Ardour9 が3回
# 登録されているような状態は気持ちが悪いので一緒に掃除する。
stale=0
while IFS= read -r path; do
	case $path in
	/Applications/* | /System/Applications/* | "$HOME"/Applications/*) ;;
	*) continue ;;
	esac
	# `[[ ... ]] && continue` と書くと、実体が無いとき AND リストが非ゼロで終わり
	# set -e に殺される。ゴーストが1件でもあると死ぬので if で書く。
	if [[ -e $path ]]; then continue; fi
	"$lsregister" -u "$path" 2>/dev/null || true
	echo "gone $path"
	stale=$((stale + 1))
done <<<"$registered_paths"

echo "==> 裏方 $hidden 件、ゴースト $stale 件を LaunchServices から外した"
