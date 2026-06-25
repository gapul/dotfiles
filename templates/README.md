# direnv テンプレ

プロジェクト毎に言語別の dev shell を持つためのテンプレ。

## 使い方

```bash
cp -r ~/.dotfiles/templates/node/{.envrc,flake.nix} ~/Dev/my-project/
cd ~/Dev/my-project
direnv allow                     # 初回のみ承認
```

これで `cd` した瞬間に Nix dev shell に入る(`node`/`pnpm`/`typescript` が PATH に)。

## 中身

| stack | 入るもの |
|---|---|
| `node/` | nodejs_22, pnpm, typescript |
| `python/` | python3, uv, ruff |
| `rust/` | rustc, cargo, rust-analyzer, rustfmt, clippy |

## 拡張

`flake.nix` の `packages` に追加するだけ:
```nix
packages = with pkgs; [
  nodejs_22
  pnpm
  postgresql     # ← 追加
];
```

`cd` で reload される(`direnv reload` でも明示)。
