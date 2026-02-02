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
- **Compute Engine (Managed Instance Group)**: Difyアプリケーションのホスティング環境（Docker, Docker Compose, PostgreSQLクライアント等を自動セットアップ）
- **Autoscaling**: CPU使用率に基づいて自動的にインスタンス数を調整
- **Cloud Load Balancer**: HTTPSトラフィックを複数のインスタンスに分散

**注意**: Difyアプリケーション本体は[GitHubリリースページ](https://github.com/langgenius/dify/releases)から最新版が自動ダウンロードされますが、設定と起動は手動で行う必要があります。

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

### Difyのセットアップ（手動）

Terraformでインフラがデプロイされた後、各インスタンスでDifyの設定と起動を手動で行う必要があります：

1. **インスタンスへの接続**:
   ```bash
   # インスタンスグループの最初のインスタンスを取得
   REGION=$(terraform output -raw region)
   MIG_NAME=$(terraform output -raw instance_group_manager_name)
   INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances $MIG_NAME --region=$REGION --format="value(instance.basename())" --limit=1)
   ZONE=$(terraform output -raw primary_zone)
   
   # SSHで接続
   gcloud compute ssh $INSTANCE_NAME --zone=$ZONE
   ```

2. **Difyのダウンロード確認**:
   ```bash
   # Difyがダウンロードされていることを確認
   ls -la /opt/dify/
   ```

3. **環境設定ファイルの作成**:
   ```bash
   cd /opt/dify/docker
   # .envファイルを作成し、必要な環境変数を設定
   # Terraformの出力値を参照してください
   ```

4. **Difyの起動**:
   ```bash
   # Docker Composeでサービスを起動
   docker-compose up -d
   ```

5. **起動確認**:
   ```bash
   # サービスが正常に起動しているか確認
   docker-compose ps
   docker-compose logs
   ```

**注意**: スタートアップスクリプトでは以下が自動的に実行されます：
- Docker と Docker Composeのインストール
- PostgreSQLクライアントのインストール
- pgvector拡張機能の有効化
- GitHubから最新のDifyリリースをダウンロード (`/opt/dify`)

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

Difyのバージョンをアップグレードする場合は、各インスタンスで手動で行います：

1. **インスタンスに接続**:
   ```bash
   gcloud compute ssh INSTANCE_NAME --zone=ZONE
   ```

2. **新しいバージョンをダウンロード**:
   ```bash
   cd /opt/dify
   # 現在のサービスを停止
   docker-compose down
   
   # 既存のファイルをバックアップ
   sudo mv /opt/dify /opt/dify.backup
   
   # 新しいバージョンをダウンロード
   sudo mkdir -p /opt/dify
   cd /opt/dify
   DIFY_VERSION="0.15.0"  # 希望のバージョン
   curl -L "https://github.com/langgenius/dify/archive/refs/tags/$DIFY_VERSION.zip" -o dify.zip
   unzip -q dify.zip
   rm dify.zip
   mv dify-*/* .
   rmdir dify-*/
   ```

3. **設定ファイルを復元して起動**:
   ```bash
   # 必要に応じて設定ファイルを復元
   # サービスを再起動
   cd /opt/dify/docker
   docker-compose up -d
   ```

**注意**: すべてのインスタンスで同じバージョンを実行することを推奨します。

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
# インスタンスのシリアルポート出力を確認（スタートアップスクリプトのログ）
gcloud compute instances get-serial-port-output INSTANCE_NAME

# SSHでインスタンスに接続
gcloud compute ssh INSTANCE_NAME

# Difyがダウンロードされているか確認
ls -la /opt/dify/

# Docker Composeのログを確認（Difyを起動している場合）
cd /opt/dify/docker
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
