# direnv templates

Templates for giving a project its own per-language dev shell.

## Using them

```bash
cp -r ~/.dotfiles/templates/node/{.envrc,flake.nix} ~/Dev/my-project/
cd ~/Dev/my-project
direnv allow                     # approve once
```

After that, entering the directory drops you into the Nix dev shell, with `node`, `pnpm` and
`typescript` on PATH.

## What each one contains

| Stack | Packages |
|---|---|
| `node/` | nodejs_22, pnpm, typescript |
| `python/` | python3, uv, ruff |
| `rust/` | rustc, cargo, rust-analyzer, rustfmt, clippy |

## Extending one

Add to `packages` in `flake.nix`:

```nix
packages = with pkgs; [
  nodejs_22
  pnpm
  postgresql     # added
];
```

Changing directory reloads it, and `direnv reload` does so explicitly.
