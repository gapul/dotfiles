# CodexBar 設定

`~/.config/codexbar/config.json` の実体です。out-of-store symlink で繋いであるので、
CodexBar の UI 操作がそのままこのファイルに書き込まれる。[omniwm](../../wm/omniwm/README.md) と同じ扱い。

- 配線は `nix/home/darwin.nix`。新しい mac では rebuild すればリンクが張られる。
- `providers[].codexActiveSource` に Codex アカウントの UUID が入る。このリポジトリは public だが、
  識別子だけで資格情報ではないのでそのまま追跡している。
