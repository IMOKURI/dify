# Dify on Google Cloud Platform with Terraform

このディレクトリには、DifyをGoogle Cloud Platform (GCP)にデプロイするためのTerraform設定が含まれています。

## アーキテクチャ

このTerraform設定は、以下のGCPリソースを作成します：

### マネージドサービス（データ永続化）
- **Cloud SQL for PostgreSQL (メインデータベース)**: アプリケーションのメタデータを保存
- **Cloud SQL for PostgreSQL with pgvector (ベクトルデータベース)**: ベクトルデータを保存
- **Memorystore for Redis**: キャッシュとCeleryブローカー
- **Cloud Storage**: ファイルストレージ

### コンピューティング
- **Compute Engine (Managed Instance Group)**: Difyアプリケーション（api, worker, worker_beat, web, sandbox, plugin_daemon, ssrf_proxy, nginx）をDocker Composeで実行
- **Autoscaling**: CPU使用率に基づいて自動的にインスタンス数を調整
- **Cloud Load Balancer**: HTTPSトラフィックを複数のインスタンスに分散

### ネットワーク
- **VPC Network**: プライベートネットワーク
- **Cloud NAT**: 外部へのインターネットアクセス
- **Firewall Rules**: セキュアなアクセス制御

## 前提条件

1. **GCPプロジェクト**: アクティブなGCPプロジェクトが必要です
2. **Terraform**: バージョン 1.0以上をインストール
3. **gcloud CLI**: 認証に必要
4. **有効化が必要なAPI**:
   ```bash
   gcloud services enable compute.googleapis.com
   gcloud services enable sqladmin.googleapis.com
   gcloud services enable redis.googleapis.com
   gcloud services enable storage-api.googleapis.com
   gcloud services enable servicenetworking.googleapis.com
   gcloud services enable iam.googleapis.com
   ```

## セットアップ手順

### 1. 認証設定

```bash
# GCPにログイン
gcloud init
gcloud auth login
gcloud auth application-default login
```

### 2. 設定ファイルの準備

```bash
# terraform.tfvars.exampleをコピー
cp terraform.tfvars.example terraform.tfvars

# terraform.tfvarsを編集して、適切な値を設定
# 特に以下の値は必ず変更してください：
# - project_id
# - db_password
# - pgvector_password
# - secret_key
```

### 3. Terraformの初期化

```bash
terraform init
```

### 4. プランの確認

```bash
terraform plan
```

### 5. リソースのデプロイ

```bash
terraform apply
```

デプロイには15-30分程度かかります。

### 6. 出力情報の確認

```bash
terraform output
```

以下の重要な情報が表示されます：
- `load_balancer_ip`: ロードバランサーのパブリックIPアドレス
- `access_url_http`: HTTPアクセスURL
- その他のリソース情報

## デプロイ後の設定

### pgvector拡張機能の有効化

ベクトルデータベースでpgvector拡張機能を有効化します：

```bash
# Cloud SQL Proxyを使用してデータベースに接続
gcloud sql connect $(terraform output -raw vector_database_instance_name) --user=postgres

# PostgreSQLに接続後、以下のSQLを実行
CREATE EXTENSION IF NOT EXISTS vector;
\q
```

または、Cloud Shellから直接実行：

```bash
VECTOR_INSTANCE=$(terraform output -raw vector_database_instance_name)
PGVECTOR_DB=$(terraform output -raw vector_database_name)
gcloud sql connect $VECTOR_INSTANCE --user=postgres --database=$PGVECTOR_DB -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### DNSの設定

ロードバランサーのIPアドレスを使用して、DNSレコードを設定します：

```bash
# ロードバランサーのIPを取得
terraform output load_balancer_ip
```

### URLの更新

1. `terraform.tfvars`ファイルで以下の変数を更新：
   ```hcl
   console_api_url = "https://your-domain.com"
   console_web_url = "https://your-domain.com"
   service_api_url = "https://your-domain.com"
   app_api_url     = "https://your-domain.com"
   app_web_url     = "https://your-domain.com"
   files_url       = "https://your-domain.com"
   ```

2. 変更を適用：
   ```bash
   terraform apply
   ```

### HTTPSの有効化

1. SSL証明書を取得（Let's Encryptなど）

2. `terraform.tfvars`を更新：
   ```hcl
   enable_https    = true
   ssl_certificate = file("path/to/certificate.crt")
   ssl_private_key = file("path/to/private.key")
   ```

3. 変更を適用：
   ```bash
   terraform apply
   ```

## 運用管理

### スケーリング

インスタンス数を変更する場合：

```hcl
# terraform.tfvars
instance_count           = 3
autoscaling_min_replicas = 2
autoscaling_max_replicas = 20
```

### モニタリング

Google Cloud Consoleで以下をモニタリングできます：
- **Compute Engine > VM instances**: インスタンスの状態
- **Cloud SQL**: データベースのパフォーマンス
- **Memorystore**: Redisの使用状況
- **Cloud Load Balancing**: トラフィック統計
- **Cloud Logging**: アプリケーションログ

### バックアップ

- **Cloud SQL**: 自動バックアップが有効化されています（デフォルト：毎日2:00 AM）
- **Cloud Storage**: バージョニングが有効化されています

### アップグレード

Difyのバージョンをアップグレードする場合：

1. `terraform.tfvars`を更新：
   ```hcl
   dify_version = "1.12.0"  # 新しいバージョン
   ```

2. 変更を適用：
   ```bash
   terraform apply
   ```

インスタンスは自動的にローリングアップデートされます。

## コスト最適化

### 開発環境向け設定

```hcl
# terraform.tfvars
db_availability_type     = "ZONAL"           # REGIONAL → ZONAL
redis_tier               = "BASIC"            # STANDARD_HA → BASIC
instance_type            = "e2-standard-2"   # より小さいインスタンス
instance_count           = 1
enable_autoscaling       = false
enable_deletion_protection = false
```

### 本番環境向け設定

```hcl
# terraform.tfvars
db_availability_type     = "REGIONAL"        # 高可用性
redis_tier               = "STANDARD_HA"     # 高可用性
instance_type            = "e2-standard-4"   # 適切なリソース
instance_count           = 2
enable_autoscaling       = true
autoscaling_min_replicas = 2
autoscaling_max_replicas = 10
enable_deletion_protection = true
```

## トラブルシューティング

### インスタンスが起動しない

```bash
# インスタンスのシリアルポート出力を確認
gcloud compute instances get-serial-port-output INSTANCE_NAME

# SSHでインスタンスに接続
gcloud compute ssh INSTANCE_NAME

# Docker Composeのログを確認
cd /opt/dify
sudo docker-compose logs
```

### データベース接続エラー

```bash
# Cloud SQLへの接続を確認
gcloud sql instances describe INSTANCE_NAME

# プライベートIP接続が有効か確認
gcloud services vpc-peerings list --network=NETWORK_NAME
```

### ロードバランサーのヘルスチェック失敗

```bash
# バックエンドサービスのヘルスステータスを確認
gcloud compute backend-services get-health BACKEND_SERVICE_NAME --global

# インスタンスのnginxログを確認
gcloud compute ssh INSTANCE_NAME
sudo docker-compose logs nginx
```

## クリーンアップ

リソースを削除する場合：

```bash
# 削除保護を無効化（必要に応じて）
# terraform.tfvarsで enable_deletion_protection = false に設定
terraform apply

# すべてのリソースを削除
terraform destroy
```

**注意**: この操作は元に戻せません。必要なデータは事前にバックアップしてください。

## セキュリティに関する考慮事項

1. **SSH アクセス制限**: `ssh_source_ranges`を特定のIPアドレス範囲に制限
2. **シークレット管理**: `terraform.tfvars`をバージョン管理に含めない（`.gitignore`に追加）
3. **データベースパスワード**: 強力なパスワードを使用
4. **削除保護**: 本番環境では`enable_deletion_protection = true`を設定
5. **HTTPS**: 本番環境では必ずHTTPSを有効化

## サポートと貢献

問題が発生した場合は、[Dify GitHubリポジトリ](https://github.com/langgenius/dify)でIssueを作成してください。

## ライセンス

このTerraform設定はDifyプロジェクトと同じライセンスの下で提供されています。
