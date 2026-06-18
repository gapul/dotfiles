# dotfiles 操作集
# `just` で一覧、`just <task>` で実行
# https://just.systems

set shell := ["bash", "-cu"]

flake := justfile_directory() + "/nix"

# デフォルト: タスク一覧
default:
    @just --list

# システム + ユーザー 両方再構築 (普段使い)
rebuild:
    nh os switch
    nh home switch

# flake input 更新 → rebuild
update:
    nix flake update --flake {{flake}}
    just rebuild

# 構文/型チェック (ビルドはしない)
check:
    nix flake check --no-build {{flake}}

# 暗号化 secrets を sops で編集
secrets-edit:
    sops {{justfile_directory()}}/secrets/secrets.yaml

# secrets を全 recipient で再暗号化 (.sops.yaml 変更後に走らせる)
secrets-rekey:
    sops updatekeys {{justfile_directory()}}/secrets/secrets.yaml

# git pre-commit hook をインストール (新Macで一度だけ)
pre-commit-install:
    pre-commit install

# 30 日より古い世代を削除 + nix store gc
gc:
    nh clean all --keep 5 --keep-since 7d

# このマシンの差分 (current vs. flake) を表示
diff:
    nh os build

# remote-env を別ホストで使う
ssh host:
    nssh {{host}}
