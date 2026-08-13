# Claude Code

母艦とリモート (nssh 先) で持ち方が違う。

## 母艦 — まるごと symlink

`nix/home/workstation.nix` が out-of-store symlink を張っていて、ここにあるファイルが実体。

| 実体 | リンク先 |
| --- | --- |
| `settings.json` | `$CLAUDE_CONFIG_DIR/settings.json` |
| `CLAUDE.md` | `$CLAUDE_CONFIG_DIR/CLAUDE.md` |
| `hooks/` `output-styles/` `bin/` | 同名のディレクトリ |
| `skills/{english-vocab,gapul-writing-voice,step-by-step-tutor}` | `skills/` の下 |

`settings.json` をまるごと持てるのは、母艦が `defaultMode: bypassPermissions` で
`permissions.allow` が育たないから。TUI からの書き戻しはそのままこのファイルに落ちるので、
`git diff` に出てきたらコミットすればいい。

セッション履歴・`.claude.json` (資格情報)・`settings.local.json` は state なので持たない。
vendored な skill (cloudflare/* など) も上流から取り直せるので管理しない。

## リモート (nssh 先) — 管理キーだけ merge

リモートは事情が違う。`~/.claude/settings.json` は承認のたびに `permissions.allow` が育つ
ホスト所有のファイルで、symlink にすると nssh の `reset --hard` で承認済みの許可が毎回消える。

そこで `settings.remote.json` の**管理キーだけ**を、ホストの既存 JSON へ
`scripts/merge-claude-settings.py` が上書き merge する。`~/.bashrc` に `bashrc.remote` を読む
行だけ足すのと同じ考え方で、管理外のキーはホスト側にそのまま残す。

- 管理対象: `theme` / `effortLevel`
- 管理外 (ホスト所有): `permissions` / `enabledPlugins` / `skipDangerousModePermissionPrompt`

管理対象は**母艦の `settings.json` が実際に持っているキー**に限る。母艦が書いていない
キーを配ると、母艦は既定値・リモートだけ明示値という食い違いが生まれ、下の「母艦が正」
が成り立たなくなる。`tui` / `inputNeededNotifEnabled` / `agentPushNotifEnabled` は
リモート側の値から起こしてしまったもので、母艦に無いので外した (2026-08-13)。
既に配ってしまったホストの値は残るが、以後はホスト所有として扱う。

`CLAUDE.md` と自作 skill は書き換わらないので、リモートでも普通に symlink する。
`hooks/` `output-styles/` `bin/` は母艦のデスクトップ前提 (osascript 通知 / herdr /
Notion MCP) なので持ち込まない。

このスクリプトを母艦の `settings.json` へ向けてはいけない。書き込みが tmp+rename なので、
nix が張った symlink を実ファイルで置き換えて追跡を切る。母艦では `--adopt` (読むだけ) の
向きでのみ使う。

## どちらが勝つか — クライアント端末が正

管理キーの値は接続元の母艦を正とする。リモートで設定をいじっても、それはそのホスト限りの
一時的なものとして次の merge で上書きされる。値の更新は母艦から吸い上げる向きで行う。

```
just claude-settings-adopt     # 母艦の現在値を settings.remote.json へ取り込む
```

吸い上げるのは `settings.remote.json` が既に持っている管理キーだけで、キーの集合は増えない
(`permissions` を巻き込まないため)。新しく管理したいキーがあるときは、先に
`settings.remote.json` へそのキーを手で足してから `adopt` を走らせる。

## theme = auto とライト/ダーク追従

`auto` は TUI 上の表示が "Auto (match terminal)" で、**OS ではなく端末**を見る。
実装は端末への OSC 11 (背景色問い合わせ) の応答 `rgb:RRRR/GGGG/BBBB` を読み、
取れないときは `COLORFGBG` にフォールバックする。

つまり ssh 越しでも、応答するのは母艦の ghostty なので**そのまま追従する**。
`nix/lib/theme.nix` の dark/light 2 端点や `theme-watch` のような side channel は
Claude には要らない。

ただし tmux の内側では OSC 11 に応答するのが tmux 自身になるため、外側の ghostty まで
問い合わせが届くかは tmux のバージョン依存。ここは nvim の `&background` 自動判定と同じ
制約で、`configs/editors/nvim/lua/plugins/auto-dark-mode.lua` の OSC 111 に関する
コメントも参照。

## 適用

- 母艦: `just rebuild`
- リモート: `nssh <host>`
- 手で: `python3 scripts/merge-claude-settings.py ~/.claude/settings.json`
