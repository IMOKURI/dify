# Dify GCP Deployment with Terraform

このディレクトリには、Dify を Google Cloud Platform (GCP) にデプロイするための Terraform コードが含まれています。

## アーキテクチャ

このデプロイメントでは、以下の GCP サービスを使用します：

### インフラストラクチャ
- **GKE (Google Kubernetes Engine)**: アプリケーションコンテナのオーケストレーション
- **Cloud SQL (PostgreSQL)**: メインデータベース
- **Memorystore for Redis**: キャッシュとメッセージブローカー
- **Cloud Storage (GCS)**: ファイルストレージ
- **VPC**: ネットワーキング
- **Secret Manager**: 機密情報の管理
- **Cloud Load Balancing**: 負荷分散

### デプロイされるサービス
- **API**: Dify API サーバー (複数レプリカ)
- **Worker**: Celery ワーカー (複数レプリカ)
- **Worker Beat**: Celery スケジューラー
- **Web**: フロントエンドアプリケーション
- **Sandbox**: コード実行環境
- **Weaviate**: ベクトルデータベース
- **SSRF Proxy**: SSRF 保護用プロキシ
- **Plugin Daemon**: プラグイン管理デーモン

## 前提条件

1. Google Cloud プロジェクトが作成されていること
2. 以下のツールがインストールされていること:
   - [Terraform](https://www.terraform.io/downloads.html) (>= 1.0)
   - [gcloud CLI](https://cloud.google.com/sdk/docs/install)
   - [kubectl](https://kubernetes.io/docs/tasks/tools/)

3. gcloud CLI で認証されていること:
```bash
gcloud auth login
gcloud auth application-default login
```

4. 必要な GCP API が有効化されていること:
```bash
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable redis.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable servicenetworking.googleapis.com
gcloud services enable storage-api.googleapis.com
```

## セットアップ手順

### 1. Terraform 変数の設定

`terraform.tfvars` ファイルを作成します:

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集して、プロジェクト固有の値を設定します:

```hcl
project_id  = "your-gcp-project-id"
region      = "asia-northeast1"
environment = "production"

# データベースパスワードやシークレットキーなどを変更してください
db_password  = "STRONG_PASSWORD_HERE"
secret_key   = "STRONG_SECRET_KEY_HERE"
```

### 2. Terraform の初期化と実行

```bash
# Terraform の初期化
terraform init

# プランの確認
terraform plan

# リソースの作成
terraform apply
```

### 3. GKE クラスターへの接続

```bash
# クラスター認証情報の取得
gcloud container clusters get-credentials $(terraform output -raw gke_cluster_name) \
  --region $(terraform output -raw gke_cluster_location) \
  --project YOUR_PROJECT_ID
```

### 4. Kubernetes リソースのデプロイ

#### 4.1 データベース接続情報の ConfigMap 作成

```bash
# Cloud SQL の接続情報を取得
POSTGRES_HOST=$(terraform output -raw postgres_private_ip)
REDIS_HOST=$(terraform output -raw redis_host)
REDIS_PORT=$(terraform output -raw redis_port)
BUCKET_NAME=$(terraform output -raw storage_bucket_name)

# ConfigMap を作成
kubectl create configmap dify-db-config \
  --from-literal=DB_HOST=${POSTGRES_HOST} \
  --from-literal=REDIS_HOST=${REDIS_HOST} \
  --from-literal=REDIS_PORT=${REDIS_PORT} \
  --namespace=dify
```

#### 4.2 Secret の更新

`k8s/secrets.yaml` を編集して、以下の値を更新します:
- `DB_PASSWORD`: Terraform で設定したデータベースパスワード
- `SECRET_KEY`: アプリケーションのシークレットキー
- `GOOGLE_STORAGE_BUCKET_NAME`: Terraform で作成された GCS バケット名
- その他必要なシークレット

```bash
kubectl apply -f k8s/secrets.yaml
```

#### 4.3 すべての Kubernetes リソースをデプロイ

```bash
# Namespace の作成
kubectl apply -f k8s/namespace.yaml

# ServiceAccount とRBAC
kubectl apply -f k8s/serviceaccount.yaml

# ConfigMap
kubectl apply -f k8s/configmap.yaml

# Persistent Volumes (注: ReadWriteMany が必要な場合は Filestore などの設定が必要)
kubectl apply -f k8s/persistent-volumes.yaml

# アプリケーションのデプロイ
kubectl apply -f k8s/weaviate-statefulset.yaml
kubectl apply -f k8s/ssrf-proxy-deployment.yaml
kubectl apply -f k8s/sandbox-deployment.yaml
kubectl apply -f k8s/plugin-daemon-deployment.yaml
kubectl apply -f k8s/api-deployment.yaml
kubectl apply -f k8s/worker-deployment.yaml
kubectl apply -f k8s/web-deployment.yaml

# Ingress の作成 (ドメイン名を設定後)
kubectl apply -f k8s/ingress.yaml
```

### 5. 静的 IP アドレスの予約（オプション）

カスタムドメインを使用する場合:

```bash
# グローバル静的 IP の予約
gcloud compute addresses create dify-static-ip --global

# IP アドレスの確認
gcloud compute addresses describe dify-static-ip --global
```

この IP アドレスを DNS レコードに設定します。

### 6. デプロイ状態の確認

```bash
# Pod の状態を確認
kubectl get pods -n dify

# サービスの確認
kubectl get svc -n dify

# Ingress の確認
kubectl get ingress -n dify

# ログの確認
kubectl logs -f deployment/api -n dify
kubectl logs -f deployment/worker -n dify
```

## スケーリング

### 水平スケーリング

```bash
# API のレプリカ数を増やす
kubectl scale deployment api --replicas=3 -n dify

# Worker のレプリカ数を増やす
kubectl scale deployment worker --replicas=4 -n dify
```

### 垂直スケーリング

`variables.tf` で以下のパラメータを調整して `terraform apply`:

- `gke_machine_type`: ノードのマシンタイプ
- `db_tier`: Cloud SQL のインスタンスサイズ
- `redis_memory_size_gb`: Redis のメモリサイズ

## モニタリング

### Cloud Monitoring でのメトリクス確認

```bash
# GCP Console でモニタリングダッシュボードを開く
echo "https://console.cloud.google.com/monitoring?project=$(gcloud config get-value project)"
```

### ログの確認

```bash
# Cloud Logging でログを確認
gcloud logging read "resource.type=k8s_container AND resource.labels.namespace_name=dify" --limit 50
```

## バックアップとリストア

### Cloud SQL のバックアップ

自動バックアップは有効になっています。手動バックアップを作成する場合:

```bash
gcloud sql backups create --instance=dify-postgres-production
```

### ストレージのバックアップ

```bash
# GCS バケットのバージョニングは有効になっています
# 必要に応じて別のバケットにコピー
gsutil -m cp -r gs://SOURCE_BUCKET gs://BACKUP_BUCKET
```

## トラブルシューティング

### Pod が起動しない

```bash
# Pod の詳細を確認
kubectl describe pod POD_NAME -n dify

# イベントを確認
kubectl get events -n dify --sort-by='.lastTimestamp'
```

### データベース接続エラー

```bash
# Cloud SQL Proxy を使用してローカルからテスト
cloud_sql_proxy -instances=CONNECTION_NAME=tcp:5432
```

### ストレージ権限エラー

Workload Identity が正しく設定されているか確認:

```bash
kubectl describe serviceaccount dify-sa -n dify
```

## クリーンアップ

リソースを削除する場合:

```bash
# Kubernetes リソースの削除
kubectl delete namespace dify

# Terraform で作成したリソースの削除
terraform destroy
```

**注意**: `terraform destroy` を実行する前に、重要なデータがバックアップされていることを確認してください。

## セキュリティ考慮事項

1. **シークレット管理**: 本番環境では、Kubernetes Secrets の代わりに Google Secret Manager と External Secrets Operator の使用を推奨
2. **ネットワーク**: 必要に応じて Firewall ルールを制限
3. **IAM**: 最小権限の原則に従ってサービスアカウントの権限を調整
4. **SSL/TLS**: Ingress で Google マネージド証明書を使用
5. **データベース**: Cloud SQL のプライベート IP を使用し、SSL 接続を強制

## コスト最適化

1. **Preemptible VM**: 開発環境では Preemptible ノードの使用を検討
2. **オートスケーリング**: GKE Cluster Autoscaler を活用
3. **ストレージクラス**: アクセス頻度に応じて適切なストレージクラスを選択
4. **リージョン選択**: データ転送コストを考慮してリージョンを選択

## サポート

問題が発生した場合は、以下を確認してください:

1. [Dify Documentation](https://docs.dify.ai/)
2. [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
3. GitHub Issues

## ライセンス

このデプロイメント構成は Dify プロジェクトと同じライセンスに従います。
