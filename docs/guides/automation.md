# 🤖 自動化システムガイド

> **Phase 4.5 エンタープライズ自動化・運用システムの完全活用ガイド**

## 🎯 概要

Phase 4.5で実装された自動化システムは、Infrastructure as Code (IaC)、Kubernetes管理、マルチクラウド統合、CI/CD、監視・ログ集約を統合した包括的な運用自動化環境です。

## 🏗️ システム構成

```
automation/
├── iac/           # Infrastructure as Code
├── kubernetes/    # Kubernetes管理
├── cloud/         # マルチクラウド統合  
├── cicd/          # CI/CD Pipeline
└── monitoring/    # 監視・ログ集約
```

---

## 🚀 基本操作

### システム状況確認
```bash
# 自動化システム全体のヘルスチェック
auto-health

# 各コンポーネント個別確認
automation-health
```

### プロファイル管理
```bash
# 現在のプロファイル確認
echo $DOTFILES_AUTO_PROFILE

# プロファイル変更
export DOTFILES_AUTO_PROFILE="enterprise"  # minimal/standard/full/enterprise
just rebuild
```

---

## 🏗️ Infrastructure as Code (IaC)

### Terraform管理

#### プロジェクト初期化
```bash
# IaC プロジェクト作成
iac-init my-infrastructure terraform dev

# 環境別設定確認
ls environments/
# dev/ staging/ prod/
```

#### インフラ操作
```bash
# インフラ状況確認
infra status

# 環境別プランニング
infra plan dev
infra plan prod

# インフラ適用
infra apply dev      # 開発環境
infra apply staging  # ステージング環境
infra apply prod     # 本番環境（要確認）

# インフラ削除（注意）
infra destroy dev
```

### Ansible統合
```bash
# Ansible Playbook実行
ansible-deploy my-playbook.yml dev

# インベントリ管理
ansible-inventory --list

# 設定同期
ansible-sync-config all
```

### Pulumi支援（fullプロファイル以上）
```bash
# Pulumi プロジェクト初期化
pulumi new aws-typescript
pulumi up

# スタック管理
pulumi stack ls
pulumi stack select production
```

---

## ☸️ Kubernetes管理

### クラスター操作

#### 基本クラスター管理
```bash
# クラスター状況確認
k8s-cluster status

# クラスター作成・削除
k8s-cluster create dev-cluster
k8s-cluster delete old-cluster

# ノード管理
k8s-cluster scale my-cluster 5
k8s-cluster upgrade my-cluster v1.28.0
```

#### アプリケーション管理
```bash
# アプリケーションデプロイ
k8s-app deploy my-app dev
k8s-app deploy my-app production

# スケーリング
k8s-app scale my-app 3

# ローリングアップデート
k8s-app update my-app v2.0.0

# ロールバック
k8s-app rollback my-app v1.9.0
```

### Helm Chart管理
```bash
# Helm Chart検索・インストール
helm search repo prometheus
helm install monitoring prometheus-community/kube-prometheus-stack

# カスタムChart作成
helm create my-chart
helm package my-chart/
helm install my-release ./my-chart-0.1.0.tgz
```

### ArgoCD GitOps（standardプロファイル以上）
```bash
# ArgoCD 状況確認
argocd app list

# アプリケーション登録
argocd app create my-app \
  --repo https://github.com/my-org/my-app-config \
  --path ./k8s \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default

# 同期・ロールバック
argocd app sync my-app
argocd app rollback my-app 123
```

---

## ☁️ マルチクラウド統合

### プロバイダー状況確認
```bash
# 全プロバイダー状況
cloud-check-status

# 個別プロバイダー
cloud-check-status aws
cloud-check-status gcp
cloud-check-status azure
```

### AWS管理
```bash
# プロファイル切り替え
aws-profile dev
aws-profile production

# リージョン切り替え
aws-region us-west-2
aws-region ap-northeast-1

# リソース確認
cloud-resources aws
```

### Google Cloud管理
```bash
# プロジェクト切り替え
gcloud config set project my-dev-project
gcloud config set project my-prod-project

# リソース確認
cloud-resources gcp
```

### コスト管理
```bash
# 月次コスト確認
cloud-costs aws month
cloud-costs gcp month

# コスト最適化アドバイス
cloud-estimate

# バックアップ
cloud-backup ./important-data s3://my-backup-bucket
```

### セキュリティスキャン
```bash
# インフラセキュリティスキャン
cloud-security-scan terraform ./infrastructure
cloud-security-scan kubernetes ./k8s-manifests
cloud-security-scan aws

# コンプライアンスチェック
cloud-security-scan all
```

---

## 🚀 CI/CD Pipeline

### パイプライン管理

#### プロジェクト初期化
```bash
# CI/CD パイプライン作成
cicd-init nodejs github my-project
cicd-init python gitlab my-api
cicd-init golang jenkins my-service
```

#### パイプライン監視
```bash
# パイプライン状況確認
cicd-monitor status

# 実行ログ確認
cicd-monitor logs github
cicd-monitor logs gitlab

# パイプライン メトリクス
cicd-monitor metrics

# ヘルスチェック
cicd-monitor health
```

### GitHub Actions
```bash
# ワークフロー実行確認
gha                 # gh run list
gha-watch           # gh run watch  
gha-logs            # gh run view --log

# パイプライン手動実行
trigger-pipeline main
trigger-pipeline feature/new-feature
```

### GitLab CI (gitlabCISupportプロファイル)
```bash
# GitLab Runner状況
gitlab-runner list
gitlab-runner status

# パイプライン実行
gitlab-ci-trigger my-project main
```

### デプロイメント管理
```bash
# 環境別デプロイ
deploy-env staging    # ステージング環境
deploy-env production # 本番環境（要確認）

# パイプライン概要
pipeline-overview
```

---

## 📊 監視・ログ集約

### 監視スタック管理

#### 監視システム初期化
```bash
# Prometheus スタック
monitoring-init prometheus

# Loki ログスタック
monitoring-init loki

# 統合スタック起動
cd monitoring && docker-compose up -d
```

#### ダッシュボード管理
```bash
# 監視ダッシュボード状況
monitoring-dashboard status

# システムメトリクス
monitoring-dashboard metrics
mon-metrics

# アラート確認
monitoring-dashboard alerts
mon-alerts

# ログ確認
monitoring-dashboard logs prometheus
monitoring-dashboard logs grafana
```

### 統合監視アクセス
- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090
- **Alertmanager**: http://localhost:9093
- **Loki**: http://localhost:3100

### アラート管理
```bash
# テストアラート送信
test-alert high-cpu-usage
test-alert disk-space-low

# アラート設定確認
monitoring-dashboard alerts

# Slack/Email通知設定
# → monitoring/alertmanager/config/alertmanager.yml を編集
```

### ログ分析
```bash
# ログクエリ（Loki）
logcli query '{job="containers"}' --since=1h
logcli query '{level="error"}' --since=24h

# システムログ監視
logs prometheus
logs grafana
logs containers
```

---

## 🔄 マルチ環境デプロイメント

### デプロイメント管理システム

#### 初期化
```bash
# マルチ環境デプロイ構造作成
deploy-manager init

# 環境確認
deploy-manager status
```

#### デプロイメント実行
```bash
# 開発環境デプロイ
deploy-manager deploy dev my-application

# ステージング環境デプロイ
deploy-manager deploy staging my-application

# 本番環境デプロイ（要確認）
deploy-manager deploy prod my-application
```

#### プロモーション
```bash
# ステージング→本番プロモーション
deploy-manager promote staging my-application prod

# ロールバック
deploy-manager rollback prod my-application v1.2.0
```

### 環境管理
```bash
# 環境切り替え
auto-env dev        # 開発環境
auto-env staging    # ステージング環境  
auto-env prod       # 本番環境

# 現在の環境状況
auto-status
```

---

## 🔧 高度な運用

### バックアップ・災害復旧
```bash
# 監視データバックアップ
monitoring-dashboard backup

# 設定バックアップ
tar czf dotfiles-backup-$(date +%Y%m%d).tar.gz ~/.config/dotfiles

# クラウドバックアップ
cloud-backup /important/data s3://backup-bucket
```

### パフォーマンス最適化
```bash
# システムメトリクス確認
metrics

# リソース使用状況
monitoring-dashboard metrics

# 自動化システム最適化
auto-health
automation-health
```

### セキュリティ・コンプライアンス
```bash
# セキュリティスキャン
cloud-security-scan all

# コンプライアンスチェック
security-compliance-check

# 監査ログ確認
audit-log-review
```

---

## 🆘 トラブルシューティング

### よくある問題

#### 自動化システムが起動しない
```bash
# コンポーネント確認
auto-health

# Docker状況確認
docker ps | grep -E "(prometheus|grafana|loki)"

# 再初期化
monitoring-init prometheus
cd monitoring && docker-compose restart
```

#### Kubernetes接続エラー
```bash
# Kubeconfig確認
kubectl config current-context
kubectl cluster-info

# 認証確認
kubectl auth can-i get pods

# クラスター再接続
k8s-cluster reconnect
```

#### クラウドプロバイダー認証エラー
```bash
# AWS認証確認
aws sts get-caller-identity

# GCP認証確認
gcloud auth list

# 再認証
aws configure sso
gcloud auth login
```

### ログ・診断
```bash
# システム全体診断
automation-health

# 詳細ログ
cicd-monitor logs all
monitoring-dashboard logs all

# 設定検証
cd nix/platforms && nix flake check --impure
```

---

## 📚 参考リソース

### 設定ファイル
- **IaC設定**: `nix/platforms/common/automation/iac/`
- **Kubernetes設定**: `nix/platforms/common/automation/kubernetes/`
- **監視設定**: `nix/platforms/common/automation/monitoring/`

### 外部ドキュメント
- [Terraform Documentation](https://terraform.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [ArgoCD Documentation](https://argoproj.github.io/argo-cd/)

### 関連ガイド
- [開発環境ガイド](DEVELOPMENT_ENVIRONMENT_GUIDE.md)
- [セキュリティガイド](../SECURITY.md)
- [AI システム詳細](../CLAUDE.md)

---

*このガイドで自動化システムの活用に関する疑問が解決しない場合は、[Issues](https://github.com/gapul/dotfiles/issues)で質問してください。*