# OmniWM 設定

`~/.config/omniwm/settings.toml` の実体です。out-of-store symlink で繋いであるので、
OmniWM の GUI で設定を変えるとこのファイルが直接書き換わる。

- 設定を nix で生成はしない。OmniWM 自身が書き戻す（キーはソート済み、float はフル精度、
  バージョンが上がるとキーが増減する）ので、store の読み取り専用シンボリックリンクだと保存できない。
  out-of-store symlink なら書き込みがそのままリポジトリに届く。
- 配線は `nix/home/darwin.nix`。新しい mac では rebuild すればリンクが張られる。
- 差分は GUI をいじったときに出るので、`git diff` に現れたら普通にコミットすればいい。
- OmniWM が tmp+rename で書くと symlink が実ファイルに置き換わって追跡が切れる。
  その場合は次の rebuild で `.hm-bak` が残るので気づける（変更は失われるがファイルは無事）。
