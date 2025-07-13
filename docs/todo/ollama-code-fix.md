# Ollama設定コードの修正 - TODO

**ID**: todo-6  
**優先度**: 高  
**推定時間**: 30分  
**ステータス**: 構文エラー発見済み

## 概要

`nix/common/development/ai-platform/ollama.nix`にLua構文エラーが存在し、Nixビルドが失敗する可能性がある。

## 問題の詳細

### 構文エラー箇所
```nix
# 行534: 不正な構文
if [< -n "''${2:-}" ]]; then
```

**問題**: `[<` は無効な構文。正しくは `[[` または `[` であるべき。

### エラーの影響
- Nixビルド時にbashスクリプト構文エラーが発生
- Ollama管理機能が正常に動作しない
- CI/CDパイプラインでの失敗原因となる可能性

## 修正手順

### 1. 即座の修正
```bash
# ファイルを開いて修正
nvim nix/common/development/ai-platform/ollama.nix

# 534行目を確認
:534

# 修正: [< を [[ に変更
if [[ -n "''${2:-}" ]]; then
```

### 2. 修正内容の詳細

#### 修正前（エラー）
```nix
if [< -n "''${2:-}" ]]; then
  code_generation "$2" "''${3:-auto}"
else
  log_error "Usage: ollama-manager code '<prompt>' [language]"
  exit 1
fi
```

#### 修正後（正常）
```nix
if [[ -n "''${2:-}" ]]; then
  code_generation "$2" "''${3:-auto}"
else
  log_error "Usage: ollama-manager code '<prompt>' [language]"
  exit 1
fi
```

### 3. 追加の構文チェック

#### 全体的なbash構文検証
```bash
# bash構文チェック用の一時ファイル作成
grep -A 50 -B 5 'text = ' nix/common/development/ai-platform/ollama.nix | \
  sed 's/.*text = /'\'\'//g' | \
  sed 's/'\'\';//g' > /tmp/ollama-script-check.sh

# bash構文チェック実行
bash -n /tmp/ollama-script-check.sh
```

#### 修正が必要な可能性がある箇所
1. **行534**: `[<` → `[[`（確認済み）
2. **その他のif文**: 同様の構文エラーが無いか確認
3. **文字列展開**: Nixの文字列展開構文の確認

### 4. 修正後の検証

#### Nixビルドテスト
```bash
# 修正後のビルドテスト
nix flake check

# 特定モジュールのテスト
nix eval .#darwinConfigurations.default.config.dotfiles.development.ai-platform.ollama
```

#### Ollamaマネージャー機能テスト
```bash
# システム再構築
just rebuild

# Ollama管理機能テスト
ollama-manager status
ollama-manager --help
```

## 追加の改善点

### 1. エラーハンドリング強化
```bash
# より堅牢なエラーハンドリング
if [[ $# -lt 1 ]]; then
    log_error "No action specified"
    exit 1
fi

if [[ -z "${2:-}" ]]; then
    log_error "Prompt required for code generation"
    exit 1
fi
```

### 2. bash strict mode の適用確認
```bash
# 既存のstrict mode設定確認
set -euo pipefail  # 既に設定済みかチェック
```

### 3. 引用符の統一
```bash
# 一貫した引用符使用の確認
"${variable}"      # 推奨形式
'${variable}'      # リテラル文字列の場合
```

## テスト項目

### 構文テスト
- [ ] bash構文チェックが通る
- [ ] Nixビルドが成功する
- [ ] エラーメッセージが適切に表示される

### 機能テスト
- [ ] `ollama-manager status` が動作する
- [ ] `ollama-manager code "test prompt"` が動作する
- [ ] `ollama-manager --help` が適切なヘルプを表示する

### 統合テスト
- [ ] システム再構築が成功する
- [ ] AI機能が正常に動作する
- [ ] ヘルスチェックが通る

## 完了条件

- [ ] 構文エラーが完全に修正されている
- [ ] bash -n での構文チェックが通る
- [ ] nix flake check が成功する
- [ ] ollama-manager の全機能が正常動作する
- [ ] CI/CDパイプラインでエラーが発生しない

## 予防策

### 1. CI/CDでの構文チェック追加
```yaml
# .github/workflows/nix-check.yml に追加
- name: Bash syntax check
  run: |
    find . -name "*.nix" -exec grep -l "text = " {} \; | \
    xargs -I {} bash -c 'extract_bash_from_nix {} | bash -n'
```

### 2. 開発時の事前チェック
```bash
# 開発時の構文チェックスクリプト
#!/bin/bash
# scripts/check-bash-syntax.sh
find nix/ -name "*.nix" -exec grep -l 'text = ' {} \; | while read file; do
    echo "Checking bash syntax in: $file"
    # Nix文字列からbashスクリプト部分を抽出してチェック
done
```

## 関連ファイル

- `nix/common/development/ai-platform/ollama.nix` - 修正対象ファイル
- `scripts/check-bash-syntax.sh` - 構文チェックスクリプト（新規作成）
- `.github/workflows/` - CI/CD設定（改善対象）

---

**作成日**: 2025年7月13日  
**最終更新**: 2025年7月13日  
**作成者**: Claude Code Assistant  
**緊急度**: 🔴 高（即座の修正が必要）