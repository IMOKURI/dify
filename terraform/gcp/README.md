# Dify GCP Terraform Deployment

このTerraformコードは、Google Cloud Platform (GCP)上にDifyアプリケーションをデプロイするためのインフラストラクチャを構築します。

## 構成要素

このTerraformコードは以下のリソースを作成します:

- **VPCネットワーク**: 独立したネットワーク環境
- **サブネット**: VPC内のサブネット
- **ファイアウォールルール**: HTTP/HTTPS、SSH、ヘルスチェック用
- **Compute Engine VM**: Docker Compose対応のUbuntu VM
- **グローバルロードバランサー**: HTTPS終端を行うロードバランサー
- **SSL証明書**: Google管理証明書または自己署名証明書
- **静的IPアドレス**: ロードバランサー用
- **サービスアカウント**: VM用のIAM権限
- **インスタンスグループ**: ロードバランサーバックエンド
- **Cloud SQL PostgreSQL**: マネージドPostgreSQLデータベース
- **VPCピアリング**: Cloud SQLのプライベート接続

## 前提条件

1. **Google Cloud SDK**: `gcloud` コマンドがインストール済み
2. **Terraform**: バージョン 1.0 以上
3. **GCPプロジェクト**: アクティブなGCPプロジェクト
4. **認証設定**:
   ```bash
   gcloud auth application-default login
   ```
5. **必要なAPIの有効化**:
   ```bash
   gcloud services enable compute.googleapis.com
   gcloud services enable servicenetworking.googleapis.com
   gcloud services enable sqladmin.googleapis.com
   ```

## セットアップ手順

### 1. 変数ファイルの準備

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`を編集し、以下の値を設定:

```hcl
project_id = "your-gcp-project-id"
region     = "asia-northeast1"
zone       = "asia-northeast1-a"
prefix     = "dify"

# ドメイン名がある場合
domain_name = "dify.example.com"

# SSHキーを設定する場合
ssh_public_key = "ssh-rsa AAAAB3... your-email@example.com"

# Cloud SQL設定
cloudsql_tier = "db-custom-2-7680"  # 2 vCPU, 7.5GB RAM
db_name       = "dify"
db_user       = "dify"
db_password   = ""  # 空の場合はランダムパスワードを生成
```

### 2. Terraformの初期化

```bash
terraform init
```

### 3. プランの確認

```bash
terraform plan
```

### 4. インフラストラクチャのデプロイ

```bash
terraform apply
```

確認を求められたら `yes` を入力します。

### 5. デプロイ完了後の情報確認

```bash
terraform output
```

以下のような情報が表示されます:
- `load_balancer_ip`: ロードバランサーのIPアドレス
- `vm_instance_ip`: VMインスタンスのIPアドレス
- `ssh_command`: VMへのSSH接続コマンド
- `https_url`: アプリケーションのHTTPS URL
- `cloudsql_connection_name`: Cloud SQL接続名
- `cloudsql_private_ip`: Cloud SQLのプライベートIPアドレス
- `database_name`: データベース名
- `database_url`: データベース接続URL (sensitive)

データベースパスワードを確認:
```bash
terraform output database_password
```

## VM へのアクセスとDifyのデプロイ

### VMにSSH接続

```bash
# Terraformのoutputから取得したコマンドを使用
gcloud compute ssh dify-vm --zone asia-northeast1-a --project your-project-id

# または直接SSH
ssh ubuntu@<VM_INSTANCE_IP>
```

### Difyのデプロイ

VMに接続後、以下の手順でDifyをデプロイ:

```bash
# 作業ディレクトリに移動
cd /opt/dify

# Difyリポジトリをクローン
git clone https://github.com/langgenius/dify.git
cd dify/docker

# 環境変数を設定
cp .env.example .env

# Cloud SQLの接続情報を設定
# Terraformのoutputから取得した値を使用
DB_USERNAME=dify
DB_PASSWORD=<terraform output -raw database_password>
DB_HOST=<terraform output -raw cloudsql_private_ip>
DB_PORT=5432
DB_DATABASE=dify

# .envファイルを編集
nano .env

# 以下の行を更新:
# DB_USERNAME=dify
# DB_PASSWORD=<上記で取得したパスワード>
# DB_HOST=<Cloud SQLのプライベートIP>
# DB_PORT=5432
# DB_DATABASE=dify

# Docker Composeで起動
docker-compose up -d

# ログを確認
docker-compose logs -f
```

### アクセス確認

ブラウザで以下のURLにアクセス:
- HTTPSアクセス: `https://<LOAD_BALANCER_IP>` または `https://your-domain.com`

## SSL証明書の設定

### オプション1: Google管理SSL証明書 (推奨)

ドメイン名を持っている場合:

1. `terraform.tfvars`で`domain_name`を設定
2. DNSレコードを設定してドメインをロードバランサーIPに向ける
3. Googleが自動的に証明書をプロビジョニング (最大15分かかる場合があります)

```hcl
domain_name = "dify.example.com"
```

DNSレコード例:
```
A    dify.example.com    <LOAD_BALANCER_IP>
```

### オプション2: 自己署名証明書

テスト環境や内部利用の場合:

```bash
# 自己署名証明書を生成
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout private-key.pem \
  -out certificate.pem \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Dify/CN=dify.local"
```

`terraform.tfvars`に追加:
```hcl
domain_name     = ""
ssl_certificate = file("certificate.pem")
ssl_private_key = file("private-key.pem")
```

## リソースの削除

すべてのリソースを削除する場合:

```bash
terraform destroy
```

確認を求められたら `yes` を入力します。

## トラブルシューティング

### Cloud SQLへの接続確認

```bash
# VMからCloud SQLに接続テスト
gcloud compute ssh dify-vm --zone asia-northeast1-a

# PostgreSQLクライアントをインストール
sudo apt-get update
sudo apt-get install -y postgresql-client

# Cloud SQLに接続
psql "postgresql://dify:<password>@<cloudsql-private-ip>:5432/dify"
```

### Cloud SQLの状態確認

```bash
# インスタンスの一覧
gcloud sql instances list

# インスタンスの詳細
gcloud sql instances describe dify-postgres

# データベースの一覧
gcloud sql databases list --instance=dify-postgres

# ユーザーの一覧
gcloud sql users list --instance=dify-postgres
```

### ヘルスチェックが失敗する

```bash
# VMにSSHで接続
gcloud compute ssh dify-vm --zone asia-northeast1-a

# Nginxの状態確認
sudo systemctl status nginx

# Dockerコンテナの状態確認
cd /opt/dify/dify/docker
docker-compose ps

# ログ確認
docker-compose logs -f
```

### SSL証明書のプロビジョニングに時間がかかる

Google管理証明書は最大15分かかる場合があります:

```bash
# 証明書の状態確認
gcloud compute ssl-certificates list
gcloud compute ssl-certificates describe dify-ssl-cert --global
```

### ファイアウォール設定の確認

```bash
# ファイアウォールルールの確認
gcloud compute firewall-rules list --filter="network:dify-network"
```

## カスタマイズ

### マシンタイプの変更

より高性能なVMが必要な場合:

```hcl
machine_type = "n1-standard-4"  # 4 vCPUs, 15GB RAM
```

### Cloud SQLのスペック変更

より高性能なデータベースが必要な場合:

```hcl
cloudsql_tier      = "db-custom-4-15360"  # 4 vCPU, 15GB RAM
cloudsql_disk_size = 100  # 100GB
```

### 高可用性構成

本番環境ではREGIONAL構成を推奨:

```hcl
# main.tf の google_sql_database_instance リソースで
availability_type = "REGIONAL"  # ZONALからREGIONALに変更
```

### ディスクサイズの増加

```hcl
disk_size_gb = 100  # 100GB
```

### 複数のVMとオートスケーリング

本番環境では、Managed Instance Group (MIG)を使用してオートスケーリングを設定することを推奨します。

## セキュリティのベストプラクティス

1. **SSH接続の制限**: `ssh_source_ranges`を特定のIPに限定
   ```hcl
   ssh_source_ranges = ["203.0.113.0/24"]
   ```

2. **サービスアカウントの権限最小化**: 必要な権限のみを付与

3. **Cloud Armorの使用**: DDoS保護とWAF機能の追加

4. **VPCフローログの有効化**: ネットワークトラフィックの監視

5. **Cloud Loggingの活用**: ログの集約と分析

## コスト最適化

- **プリエンプティブルVM**: 開発環境では費用削減可能
- **スケジューリング**: 夜間や週末にVMを停止
- **Committed Use Discounts**: 長期利用の場合は割引契約を検討

## サポートとリソース

- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Dify Documentation](https://docs.dify.ai/)
- [GCP Load Balancer Documentation](https://cloud.google.com/load-balancing/docs)
