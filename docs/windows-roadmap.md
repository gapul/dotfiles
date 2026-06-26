# Windows 対応 ロードマップ

macOS / WSL を主軸にしてきた本 dotfiles を **Windows ネイティブ + WSL2 ハイブリッド**で
完全運用するための残作業リスト。`windows/SETUP-CHECKLIST.md` の "実機で詰める論点" を
優先度付き TODO に展開したもの。

## 実機の現状(2026-06-26 採取)

| 項目 | 状態 |
|---|---|
| pwsh | Windows PowerShell **5.1** のみ。PowerShell 7 (`Microsoft.PowerShell`) は未導入 |
| winget | v1.28.240 |
| WSL | `Ubuntu-24.04` / `Ubuntu` の 2 distro が Stopped で導入済み |
| 導入済 CLI | `git`(scoop), `nvim`, `yazi`, `gh`, `scoop`, `oh-my-posh` |
| 未導入 CLI | `starship`, `zoxide`, `fzf`, `rg`, `bat`, `fd`, `jq`, `lazygit`, `sops`, `age` |
| Nerd Font | M+ 系は導入済み。`JetBrainsMono Nerd Font` (Terminal `fontFace` の前提) は未確認 |

## configs/ のネイティブ pwsh 再利用可否

| ツール | symlink で動くか | 備考 |
|---|---|---|
| `configs/shell/starship.toml` | ✅ そのまま | `$env:STARSHIP_CONFIG` で参照 (`$PROFILE` 既設) |
| `configs/cli/gh/config.yml` | ✅ | `$env:GH_CONFIG_DIR` を向けるだけ |
| `configs/cli/bat/` | ✅ (themes のみ) | `$env:BAT_CONFIG_DIR` |
| `configs/editors/zed/` | ✅ | Zed Windows は preview だが telemetry 設定のみで無害 |
| `configs/cli/yazi/yazi.toml` | ❌ | `[opener]` が `for="macos"/"unix"` のみ。Windows 用セクション要追加 |
| `configs/editors/nvim/` | ❌ (3 か所修正) | `obsidian.lua:36` の `"open"`、`skkeleton.lua:10-16` の XDG パス直書き、`lazy.lua:39` の `~/Developer/...` |
| `configs/terminals/zellij/` | N/A | Windows ネイティブ未対応 (WSL 内のみ) |
| `configs/terminals/ghostty/` | N/A | macOS/Linux 専用 |

## WSL ↔ Windows 橋渡しの穴

| 方向 | 状態 |
|---|---|
| WSL → Windows | ✅ `pbcopy/pbpaste`(clip.exe / powershell.exe), `explorer`, `wslview`(自作), `code` ラッパー |
| Windows → WSL | ⚠️ `wsl-here` 関数のみ。SSH agent / 1Password / GPG / Git credential helper 共有は未対応 |

---

## 優先度付き TODO

### 🔴 P0(動かすため必須)

| # | 内容 | 状態 |
|---|---|---|
| P0-1 | `bootstrap.ps1` の冒頭で `Microsoft.PowerShell`(=7) を winget でインストール。PSReadLine `PredictionSource` は 5.1 同梱版で失敗する。profile も能力検出で 5.1/7 両対応に | ✅ 38efee9, (PSReadLine 検出は P1-8 と同コミット) |
| P0-2 | scoop ↔ winget 重複の診断ヘルパー `Find-DotfilesToolOverlap` を profile.ps1 に追加 + 「winget 一次 / scoop 補助」運用方針を README に明文化 | ✅ 4cdc178 |
| P0-3 | `apps.json` の全 ID 実在を機械的に検証する `verify.ps1` を追加 | ✅ 38efee9 |
| P0-4 | Nerd Font 自動化 — `DEVCOM.JetBrainsMonoNerdFont` を `apps.json` に追加 | ✅ 38efee9 |

実機検証で確定した不確実 ID の正しい名前:

| 候補名 | 正しい winget ID |
|---|---|
| sops | `SecretsOPerationS.SOPS` (3.12.2) ← Mozilla.SOPS は旧版 |
| gitleaks | `Gitleaks.Gitleaks` (8.30.1) |
| typst | `Typst.Typst` |
| bottom | `Clement.bottom` (0.14.1) |
| mpv | `shinchiro.mpv` (0.41.0) |
| jetbrains nerd font | `DEVCOM.JetBrainsMonoNerdFont` (3.3.0) |

### 🟠 P1(ネイティブ体験の完成)

| # | 内容 | 状態 |
|---|---|---|
| P1-5 | `bootstrap.ps1` に `New-DotfilesLink` 関数追加 + `gh`/`bat`/`yazi`/`nvim`/`zed` symlink + `$PROFILE` を pwsh7/5.1 両方へ + `-DryRun` 対応 | ✅ 5d1f218 |
| P1-6 | `configs/cli/yazi/yazi.toml` に `[opener]` の `for = "windows"` セクション追加(`start "" "$@"`, `tar -xf`, `nvim`, `mpv`) | ✅ d9485d4 |
| P1-7 | nvim 3 か所を `vim.fn.has("win32")` 分岐: obsidian.lua follow_url、skkeleton.lua 辞書パス、lazy.lua dev.fallback | ✅ 26e0aa7 |
| P1-8 | SOPS ネイティブ復号導線 — `$env:SOPS_AGE_KEY_FILE` 設定 + `Get-DotfilesSecret` / `Copy-DotfilesSecret` 関数 | ✅ (this commit) |

### 🟡 P2(運用品質)

| # | 内容 | 状態 |
|---|---|---|
| P2-9 | `Justfile` に `win-bootstrap` / `win-verify` / `win-fmt`(PSScriptAnalyzer)を追加 + `Casey.Just` を apps.json に追加 | ✅ d7156c1 |
| P2-10 | `check.yml` に windows-latest ジョブ追加(parse / `-DryRun` / PSScriptAnalyzer) + `.gitattributes` で BOM 維持 | ✅ 34640ca (実 CI で SUCCESS) |
| P2-11 | Windows ssh-agent サービスを bootstrap で auto-start、WSL から `npiperelay + socat` で共有 | ✅ 15de024 |
| P2-12 | scoop ↔ winget 運用方針を README に明文化(P0-2 と統合) | ✅ 4cdc178 |

### 🔵 P3(ハイブリッド体験の磨き込み)

| # | 内容 | 状態 |
|---|---|---|
| P3-13 | WT `settings.json`: defaultProfile を pwsh7 に、Windows PowerShell 5.1 を出す、Ubuntu (WSL) は維持 | ✅ (this commit) |
| P3-14 | espanso は `Espanso.Espanso` を apps.json + match/base.yml symlink で共有。SKK は Windows 専用 `nathancorvussolis.corvusskk` を apps.json に追加(macOS plist は移植不可) | ✅ (this commit) |
| P3-15 | `docs/CHEATSHEET.md` に Windows セクション追加(macOS コマンドとの対応表、ネイティブ pwsh 関数一覧、SKK の OS 別実装メモ) | ✅ 0c3197b |

### 🟣 P4(磨き込みの続き)

| # | 内容 | 状態 |
|---|---|---|
| P4-16 | profile.ps1 に `Open-Wsl` / `ConvertTo-WslPath` / `ConvertFrom-WslPath` 追加 | ✅ (this commit) |
| P4-17 | `$env:GHQ_ROOT` を `%USERPROFILE%\Developer` に設定し nvim lazy.lua の dev.path と整合。apps.json に `x-motemen.ghq` 追加 | ✅ (this commit) |
| P4-18 | Justfile に `win-upgrade` / `win-status`、`status.ps1` で宣言 ↔ 実 install の差分検出 | ✅ (this commit) |
| P4-19 | verify.ps1 / status.ps1 の `$PSScriptRoot` を param デフォルト式から本体へ移動 (5.1 で空になる挙動の回避) | ✅ 5b00bf7 |

### 🟤 P5(セルフ診断)

| # | 内容 | 状態 |
|---|---|---|
| P5-20 | `Test-DotfilesSetup` を profile.ps1 に追加 (macOS `just doctor` 相当)。configs symlink / 環境変数 / 主要ツール / 鍵 ACL / ssh-agent サービスを 5 セクションで集計 | ✅ (this commit) |
| P5-21 | `STARSHIP_CONFIG` の設定を `Get-Command starship` 条件から外し、ツール未導入でも env だけは先に設定 | ✅ (this commit) |

---

## 実装順

```
P0-1 → P0-3 → P0-4 → P0-2          (bootstrap が安定して走る)
       ↓
P1-5 → P1-6 → P1-7 → P1-8          (ネイティブで configs が読まれる)
       ↓
P2-9 → P2-10 → P2-11 → P2-12       (運用ルール化)
       ↓
P3-13 → P3-14 → P3-15              (磨き込み)
```
