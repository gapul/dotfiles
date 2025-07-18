はい、承知いたしました。
ご自身の`dotfiles`に`duti`を導入し、macOSのファイル関連付け（デフォルトで開くアプリケーション）を宣言的に管理するための仕様書を作成します。

-----

## **仕様書：`duti`導入によるmacOSファイル関連付けの宣言的管理**

**バージョン**: 1.0  
**作成日**: 2025年7月18日  
**目的**: macOSにおけるファイルタイプの関連付けをNixを用いて宣言的に管理し、環境の再現性を向上させる。

### 1\. 概要

本仕様書は、macOSのファイル関連付けを管理するコマンドラインツール`duti`を`dotfiles`システムに統合するための要件と実装手順を定義する。

実装は、既存のNixおよびHome Managerの構成に則り、**`home.fileAssociations`オプション** を利用して行う。これにより、どの拡張子をどのアプリケーションで開くかをコードで管理可能にする。

### 2\. 背景と目的

  - **現状の問題**: 現在の`dotfiles`環境では、macOSのファイル関連付けが宣言的に管理されておらず、手動での設定が必要となっている。これにより、新しい環境のセットアップ時に手作業が発生し、環境の完全な再現性が損なわれている。
  - **解決策**: `duti`はファイル関連付けを設定できるmacOS用ツールである。Home Managerは`duti`を内部的に利用する`home.fileAssociations`という宣言的なインターフェースを提供している。
  - **目的**: この仕組みを導入し、ファイル関連付けをNixのコードベースで一元管理することで、dotfilesの宣言的管理の範囲を拡大し、セットアップの自動化と環境の一貫性をさらに高める。

### 3\. 実装方針

1.  **`duti`の導入**: `duti`をHomebrew経由でNix環境の管理対象パッケージとして追加する。
2.  **設定のモジュール化**: ファイル関連付け専用のNixモジュール (`file-associations.nix`) を`nix/darwin/`ディレクトリ内に新規作成し、設定を分離する。
3.  **宣言的な設定**: 新規作成したモジュール内で`home.fileAssociations`オプションを使用し、主要な拡張子とアプリケーションの関連付けを定義する。
4.  **既存設定への統合**: 作成したモジュールをmacOSのメイン設定ファイルからインポートし、システムに適用する。

### 4\. 実装詳細

#### 4.1. `duti`パッケージの追加

`homebrew.brews`を管理しているNixファイル（例: `nix/darwin/brew.nix`）に`duti`を追加する。

```nix
# nix/darwin/brew.nix など
{ pkgs, ... }:

{
  homebrew.brews = [
    # ... 他のbrewパッケージ
    "duti" # ファイル関連付けのため追加
  ];
}
```

#### 4.2. `file-associations.nix`の新規作成

`nix/darwin/file-associations.nix` というファイルを新規に作成し、以下のように設定を記述する。

```nix
# nix/darwin/file-associations.nix
{ pkgs, ... }:

{
  # duti を利用してファイル関連付けを宣言的に管理
  home.fileAssociations = {
    # 拡張子 = "アプリケーションの.appバンドルへのパス";

    # --- 開発関連 ---
    ".md" = "/Applications/Visual Studio Code.app";
    ".ts" = "/Applications/Visual Studio Code.app";
    ".js" = "/Applications/Visual Studio Code.app";
    ".json" = "/Applications/Visual Studio Code.app";
    ".lua" = "/Applications/Visual Studio Code.app";
    ".rs" = "/Applications/Visual Studio Code.app";
    ".go" = "/Applications/Visual Studio Code.app";
    ".py" = "/Applications/Visual Studio Code.app";
    ".sh" = "/Applications/Visual Studio Code.app";
    ".nix" = "/Applications/Visual Studio Code.app";

    # --- メディア ---
    ".mp4" = "/Applications/VLC.app";
    ".mkv" = "/Applications/VLC.app";
    ".mov" = "/Applications/VLC.app";

    # --- 画像 ---
    ".png" = "/System/Applications/Preview.app";
    ".jpg" = "/System/Applications/Preview.app";
    ".jpeg" = "/System/Applications/Preview.app";
    ".gif" = "/System/Applications/Preview.app";

    # --- その他 ---
    ".pdf" = "/System/Applications/Preview.app";
    ".txt" = "/Applications/Visual Studio Code.app";

    # URLスキーム
    "http" = "/Applications/Zen.app";
    "https" = "/Applications/Zen.app";
  };
}
```

*上記は設定例です。ご自身の環境に合わせてアプリケーションのパスを調整してください。*

#### 4.3. 既存設定へのインポート

`nix/darwin/default.nix`（またはmacOS設定のエントリーポイント）に、作成した`file-associations.nix`をインポートする記述を追加する。

```nix
# nix/darwin/default.nix
{ ... }:

{
  imports = [
    # ... 他のインポート
    ./file-associations.nix # この行を追加
  ];

  # ... 他の設定
}
```

### 5\. 検証方法

1.  **ビルド**: ターミナルで`just rebuild`（または`darwin-rebuild switch --flake .`）を実行し、エラーなく完了することを確認する。
2.  **コマンドラインでの確認**:
    ```bash
    # ビルド後、ターミナルで以下のコマンドを実行し、設定が反映されているか確認
    duti -x md
    # -> "Visual Studio Code" を含むパスが表示されるはず
    duti -x pdf
    # -> "Preview.app" を含むパスが表示されるはず
    ```
3.  **Finderでの確認**:
      - `.md`ファイルを右クリックし、「情報を見る」を選択。
      - 「このアプリケーションで開く」の項目が「Visual Studio Code.app」になっていることを確認する。

### 6\. 変更・作成されるファイル

  - **（変更）** `nix/darwin/brew.nix` (またはHomebrewパッケージを管理するファイル)
  - **（新規）** `nix/darwin/file-associations.nix`
  - **（変更）** `nix/darwin/default.nix` (またはmacOS設定のエントリーポイント)