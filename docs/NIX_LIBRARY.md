# Dotfiles Phase 6 統合仕様書

## 1. 目的

本仕様書は、現在のdotfiles構成に、ワークフローを劇的に改善する複数の先進的なNixツールを統合することを目的とする。これにより、**開発体験の完全自動化**、**宣言的なセキュリティ管理**、**ビルドパフォーマンスの最適化**、そして**システムの可視性向上**を実現する。

## 2. 導入対象一覧

以下のツール群を段階的に導入する。

|   |   |   |
|---|---|---|
|**カテゴリ**|**ツール名**|**目的**|
|**コアワークフロー**|`nix-direnv`|開発環境シェルの起動高速化と自動更新|
|(必修)|`sops-nix`|宣言的なシークレット管理|
||`crane`|Rustプロジェクトのビルド高速化|
|**QoL向上**|`fastfetch`|モダンで高速なシステム情報表示|
|(あると嬉しい)|`nix-output-monitor (nom)`|ビルドログのTUIによる可視化|
||`nix-tree`|パッケージ依存関係ツリーの可視化|

## 3. 全体ワークフロー

実装は以下のステップで進めることを推奨する。各ステップは独立して検証可能であり、一度に全てを実装する必要はない。

推奨されるGitワークフロー:

mainブランチからfeature/phase6-integrationのような新しいブランチを作成し、全ての作業が完了したらmainにマージする。

1. **Step 1: Flakeの準備 (基盤整備)**
    
    - `flake.nix`に必要な`inputs`を全て追加する。
        
2. **Step 2: コアワークフローの強化 (日々の体験向上)**
    
    - `nix-direnv`を導入し、シェルの自動化を完成させる。
        
    - `sops-nix`を導入し、シークレット管理を完全に宣言化する。
        
3. **Step 3: 特定用途の強化 (ビルド最適化)**
    
    - `crane`を導入し、Rustプロジェクトのビルドを高速化する。
        
4. **Step 4: QoLツールの導入 (可視性と美観)**
    
    - `fastfetch`, `nix-output-monitor`, `nix-tree`を導入し、システムの分析と見た目を向上させる。
        

## 4. 個別実装仕様

### Step 1: Flakeの準備

#### 目的

今後の実装で必要となる全てのNix Flakeの依存関係を、最初に`flake.nix`へ集約する。

#### 実装手順

1. flake.nixのinputsを更新:
    
    以下のinputsをあなたのflake.nixに追加・統合する。
    
    ```
    # ./flake.nix
    {
      description = "Your dotfiles";
    
      inputs = {
        # --- 既存のinputs ---
        nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
        home-manager.url = "github:nix-community/home-manager";
        home-manager.inputs.nixpkgs.follows = "nixpkgs";
        # ... 他の既存inputs ...
    
        # --- Phase 6で追加するinputs ---
    
        # for Step 2
        nix-direnv.url = "github:nix-community/nix-direnv";
        sops-nix = {
          url = "github:Mic92/sops-nix";
          inputs.nixpkgs.follows = "nixpkgs";
        };
    
        # for Step 3
        crane = {
          url = "github:ipetkov/crane";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        rust-overlay = {
          url = "github:oxalica/rust-overlay";
          inputs.nixpkgs.follows = "nixpkgs";
        };
      };
    
      outputs = { self, nixpkgs, home-manager, ... }@inputs: {
        # ...
      };
    }
    ```
    
2. Flakeのロックファイルを更新:
    
    ターミナルで以下のコマンドを実行し、新しいinputsをflake.lockファイルに反映させる。
    
    ```
    nix flake update
    ```
    

#### 検証方法

コマンドがエラーなく完了し、`flake.lock`ファイルが更新されていることを確認する。

### Step 2: コアワークフローの強化

#### 2-1. `nix-direnv`の導入

- **目的:** `cd`コマンドでのディレクトリ移動時に、開発環境を高速かつ自動的にロードする。
    
- **実装手順:**
    
    1. `nix/darwin/yuki/home.nix` (または共通の`home.nix`) を編集する。
        
        ```
        # nix/darwin/yuki/home.nix
        { pkgs, ... }: {
          programs.direnv = {
            enable = true;
            # この行を追加してnix-direnvを有効化
            nix-direnv.enable = true;
          };
        }
        ```
        
- **検証方法:**
    
    1. `nix-darwin switch` を実行して設定を反映。
        
    2. `devShell`を持つプロジェクトのディレクトリに移動する。
        
    3. `direnv status` を実行し、`nix-direnv`が利用されていること、そしてシェルのロード時間が非常に短いことを確認する。
        

#### 2-2. `sops-nix`の導入

- **目的:** APIキーなどのシークレットをGitリポジトリで安全に管理し、宣言的に配備する。
    
- **実装手順:**
    
    1. **モジュールのインポート:** `flake.nix`の`outputs`セクションで、`nix-darwin`と`home-manager`の両方に`sops-nix`モジュールをインポートする。
        
        ```
        # ./flake.nix (outputsセクション)
        outputs = { self, nixpkgs, home-manager, sops-nix, ... }@inputs: {
          darwinConfigurations."your-hostname" = nixpkgs.lib.nixosSystem {
            # ...
            modules = [
              # ...
              sops-nix.nixosModules.sops # for system-wide secrets
              home-manager.darwinModules.home-manager {
                # ...
                users.yuki = { pkgs, ... }: {
                  imports = [
                    sops-nix.homeManagerModules.sops # for user-specific secrets
                    # ...
                  ];
                };
              }
            ];
          };
        };
        ```
        
    2. **`.sops.yaml`の作成:** リポジトリのルートに、暗号化ルールを定義する`.sops.yaml`を作成する。
        
        ```
        # ./.sops.yaml
        creation_rules:
          - path_regex: nix/secrets/.*\.yaml$
            encrypted_regex: ^(data|stringData)$
            # あなたのage公開鍵に置き換える
            age: age1...
        ```
        
    3. **暗号化ファイルの作成:**
        
        - `nix/secrets/` ディレクトリを作成する。
            
        - `nix/secrets/secrets.yaml` を作成し、シークレットを記述する。
            
            ```
            # nix/secrets/secrets.yaml
            github_token: "ENC[...]" # この値は後でsopsが生成
            ```
            
        - `sops --encrypt --in-place nix/secrets/secrets.yaml` を実行してファイルを暗号化する。
            
    4. **`sops-nix`設定の記述:** `nix/darwin/yuki/home.nix` などに設定を記述する。
        
        ```
        # nix/darwin/yuki/home.nix
        { pkgs, ... }: {
          sops = {
            # ageキーファイルのパスを指定
            age.keyFile = "/Users/yuki/.config/sops/age/keys.txt";
            secrets = {
              "github_token_file" = {
                # sopsで暗号化されたYAMLファイルを指定
                sopsFile = ../../secrets/secrets.yaml;
                # 復号後のファイルのパス
                path = "${config.xdg.configHome}/github-token";
              };
            };
          };
        }
        ```
        
- **検証方法:**
    
    1. `nix-darwin switch` を実行。
        
    2. `/Users/yuki/.config/github-token` が作成され、復号化されたトークンが書き込まれていることを確認する。
        

### Step 3: 特定用途の強化 (`crane`)

- **目的:** Tauriアプリなど、Rustを含むプロジェクトのビルド時間を短縮する。
    
- **実装手順:**
    
    1. **Overlayの適用:** `flake.nix`で`rust-overlay`を`nixpkgs`に適用する。
        
        ```
        # ./flake.nix (outputsセクションのletブロック内)
        let
          overlays = [ inputs.rust-overlay.overlays.default ];
          pkgs = import nixpkgs {
            system = "aarch64-darwin";
            config.allowUnfree = true;
            inherit overlays;
          };
        in # ...
        ```
        
    2. **`devShell`の更新:** Rustプロジェクト用の`devShell`（例: `nix/devshells/rust.nix`）で`crane`を利用する。
        
        ```
        # nix/devshells/rust.nix
        { pkgs, crane, ... }:
        let
          # 1. craneライブラリを初期化
          craneLib = crane.lib."${pkgs.system}".overrideToolchain (
            pkgs.rust-bin.stable.latest.default
          );
          # 2. 依存関係のみをビルドするderivationを作成
          cargoArtifacts = craneLib.buildDepsOnly {
            src = pkgs.lib.cleanSource ./path/to/your/rust/project;
          };
        in
        pkgs.mkShell {
          # 3. ビルド済み依存関係をdevShellに含める
          inputsFrom = [ cargoArtifacts ];
          packages = with pkgs; [
            # ...
          ];
        }
        ```
        
- **検証方法:**
    
    1. Rustプロジェクトのディレクトリで`nix develop`を実行。
        
    2. 初回は依存関係のビルドに時間がかかる。
        
    3. 一度`exit`し、再度`nix develop`を実行。2回目以降はキャッシュが効き、すぐにシェルに入れることを確認する。
        

### Step 4: QoLツールの導入

- **目的:** システムの分析と日々のターミナル操作をより快適で楽しいものにする。
    
- **実装手順:**
    
    1. **パッケージの追加:** `nix/common/packages.nix` のような共通ファイルに、以下のパッケージを追加する。
        
        ```
        # nix/common/packages.nix
        { pkgs }: with pkgs; [
          # ... 既存のパッケージ
          fastfetch
          nix-output-monitor
          nix-tree
        ]
        ```
        
    2. **`fastfetch`の設定:**
        
        - `configs/cli/fastfetch/` ディレクトリを作成し、設定ファイル `config.jsonc` を配置する。
            
        - `nix/common/home.nix` などで、設定ファイルをシンボリックリンクする。
            
            ```
            home.file.".config/fastfetch/config.jsonc".source = ../../configs/cli/fastfetch/config.jsonc;
            ```
            
- **検証方法:**
    
    1. `nix-darwin switch` を実行。
        
    2. ターミナルで `fastfetch` を実行し、美しいシステム情報が表示されることを確認する。
        
    3. `nom build .#some-package` を実行し、TUIが表示されることを確認する。
        
    4. `nix-tree .#some-package` を実行し、依存関係ツリーが表示されることを確認する。
        

## 5. 次のステップ

このPhase 6が完了すると、あなたのdotfilesは自動化、セキュリティ、パフォーマンスの面で現在の最高水準に達します。次のステップとしては、`deploy-rs`を使ったマルチマシン管理や、`Arion`によるコンテナオーケストレーションなど、よりインフラに近い領域への拡張が視野に入ります。