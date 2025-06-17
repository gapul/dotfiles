# 📦 Homebrew管理戦略

このドキュメントは、この`dotfiles`システムにおいて、特定のアプリケーションをNixではなくHomebrew Caskで管理する理由とその戦略を記録します。Nixエコシステムの進化に伴い、このリストは定期的に見直されるべきです。

## 🎯 基本方針

1. **Nix-First**: 可能な限りすべてのパッケージはNixで管理することを第一目標とする。
    
2. **安定性の優先**: Nixで互換性の問題やビルドエラーが発生するパッケージは、ユーザー体験を損なわないために、安定して動作するHomebrew Caskを躊躇なく利用する。
    
3. **宣言的管理の維持**: Homebrewで管理するパッケージも、`nix/darwin.nix`内の`homebrew.casks`で宣言的にリストアップし、システム全体の管理下に置く。
    

## 📋 Homebrew管理パッケージ一覧

|                        |                   |                                                                              |            |
| ---------------------- | ----------------- | ---------------------------------------------------------------------------- | ---------- |
| **Cask名**              | **Nixでのパッケージ名**   | **Homebrewで管理する理由**                                                          | **最終確認日**  |
| **macOS専用 / 深い統合**     |                   |                                                                              |            |
| `raycast`              | (なし)              | macOSのシステムAPIに深く依存するランチャー                                                    | 2025-06-17 |
| `karabiner-elements`   | (なし)              | macOSのカーネル拡張を利用するキーボードカスタマイザー                                                | 2025-06-17 |
| `jordanbaird-ice`      | (なし)              | macOSのメニューバーを直接操作するユーティリティ                                                   | 2025-06-17 |
| **Apple Silicon互換性問題** |                   |                                                                              |            |
| `vlc`                  | `vlc`             | aarch64-darwinでのビルドに失敗する既知の問題 [cite: docs/nix/apple-silicon-migration.md]    | 2025-06-17 |
| `inkscape`             | `inkscape`        | aarch64-darwinで起動はするがUIが表示されない問題 [cite: docs/nix/apple-silicon-migration.md] | 2025-06-17 |
| `gimp`                 | `gimp`            | Apple Siliconでの安定性に懸念があり、Homebrew版が推奨される                                     | 2025-06-17 |
| `krita`                | `krita`           | 複雑な依存関係のため、Apple Siliconでの安定性を優先                                             | 2025-06-17 |
| `obs`                  | `obs-studio`      | 仮想カメラなどのmacOS機能との連携がCask版の方が安定                                               | 2025-06-17 |
| `virtualbox`           | `virtualbox`      | aarch64-darwinではサポートされていない                                                   | 2025-06-17 |
| `godot`                | `godot_4`         | aarch64-darwinでのビルドが不安定な場合がある                                                | 2025-06-17 |
| **プロプライエタリ / ライセンス**   |                   |                                                                              |            |
| `microsoft-excel`      | (なし)              | Microsoft Office スイート（プロプライエタリ）                                              | 2025-06-17 |
| `microsoft-word`       | (なし)              | Microsoft Office スイート（プロプライエタリ）                                              | 2025-06-17 |
| `microsoft-powerpoint` | (なし)              | Microsoft Office スイート（プロプライエタリ）                                              | 2025-06-17 |
| `cursor`               | (なし)              | プロプライエタリなAIエディタ                                                              | 2025-06-17 |
| `claude`               | (なし)              | プロプライエタリなAIアシスタント                                                            | 2025-06-17 |
| `chatgpt`              | (なし)              | プロプライエタリなAIアシスタント                                                            | 2025-06-17 |
| `steam`                | `steam`           | 公式のmacOSクライアントの方が安定性とゲーム互換性が高い                                               | 2025-06-17 |
| `davinci-resolve`      | `davinci-resolve` | Nix版も存在するが、公式インストーラーの方が安定                                                    | 2025-06-17 |
| **特殊なTap / フォーク**      |                   |                                                                              |            |
| `floorp`               | (なし)              | Firefoxの特定フォークであり、nixpkgsに含まれていない                                            | 2025-06-17 |
| `zen-browser`          | (なし)              | Firefoxの特定フォークであり、nixpkgsに含まれていない                                            | 2025-06-17 |
