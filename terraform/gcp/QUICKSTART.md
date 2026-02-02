# Dify on GCP - クイックスタートガイド

このガイドに従って、5分でDifyをGCPにデプロイできます。

## 前提条件

- GCPプロジェクト
- `gcloud` コマンドがインストール済み
- `terraform` がインストール済み（v1.0以上）

## デプロイ手順

### 1. 認証とAPI有効化

```bash
# GCP認証
gcloud auth application-default login

# 必要なAPIを有効化
gcloud services enable compute.googleapis.com \
  servicenetworking.googleapis.com \
  sqladmin.googleapis.com
```

### 2. 設定ファイルの準備

```bash
cd terraform/gcp

# 設定ファイルをコピー
cp terraform.tfvars.example terraform.tfvars

# 最低限の設定を編集
nano terraform.tfvars
```

**必須設定（terraform.tfvars）:**

```hcl
project_id = "your-gcp-project-id"  # GCPプロジェクトID
```

その他の設定はデフォルト値が使用されます。

### 3. デプロイ実行

```bash
# 初期化
terraform init

# デプロイ
terraform apply
```

`yes` を入力して確認。約5-10分で完了します。

### 4. 接続情報の取得

```bash
# ロードバランサーのIPアドレス
terraform output load_balancer_ip

# VM接続コマンド
terraform output ssh_command

# データベース接続情報
terraform output -raw database_password
terraform output -raw database_url
```

### 5. VMにアクセスしてDifyをセットアップ

```bash
# VMに接続
$(terraform output -raw ssh_command)
```

VMに接続したら:

```bash
# Difyをクローン
cd /opt/dify
git clone https://github.com/langgenius/dify.git
cd dify/docker

# 環境設定
cp .env.example .env

# データベース情報を設定（Terraformのoutputから取得した値を使用）
nano .env
# 以下の行を更新:
# DB_USERNAME=dify
# DB_PASSWORD=<terraform output -raw database_password>
# DB_HOST=<terraform output -raw cloudsql_private_ip>
# DB_PORT=5432
# DB_DATABASE=dify

# 起動
docker-compose up -d

# ログ確認
docker-compose logs -f
```

### 6. アクセス

ブラウザで以下のURLにアクセス:

```
https://<terraform output load_balancer_ip>
```

## オプション: pgvectorを有効化

ベクトル検索が必要な場合:

```hcl
# terraform.tfvars に追加
enable_pgvector = true
```

その後、`terraform apply` を実行してpgvectorインスタンスを作成します。

拡張機能のインストール:

```bash
# Cloud SQL Proxyをダウンロード
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.8.1/cloud-sql-proxy.linux.amd64
chmod +x cloud-sql-proxy

# プロキシを起動（別ターミナル）
./cloud-sql-proxy $(terraform output -raw pgvector_connection_name)

# pgvector拡張をインストール
export PGPASSWORD=$(terraform output -raw pgvector_database_password)
psql -h 127.0.0.1 -U $(terraform output -raw pgvector_database_user) \
  -d $(terraform output -raw pgvector_database_name) \
  -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

## オプション: ドメインでSSL証明書を設定

独自ドメインを使用する場合:

```hcl
# terraform.tfvars
domain_name = "dify.example.com"
```

DNSレコードを設定:

```
A    dify.example.com    <terraform output load_balancer_ip>
```

証明書は自動的にプロビジョニングされます（最大15分）。

## リソースの削除

```bash
# terraform.tfvars または main.tf で deletion_protection を無効化
# deletion_protection = false
# pgvector_deletion_protection = false

terraform apply

# すべてのリソースを削除
terraform destroy
```

## トラブルシューティング

### SSL証明書のステータス確認

```bash
gcloud compute ssl-certificates list
```

### Cloud SQLの接続確認

```bash
# VM内で
psql "$(terraform output -raw database_url)"
```

### Dockerコンテナの確認

```bash
# VM内で
cd /opt/dify/dify/docker
docker-compose ps
docker-compose logs
```

## 詳細情報

完全なドキュメントは [README.md](README.md) を参照してください。

## サポート

- [Dify公式ドキュメント](https://docs.dify.ai/)
- [GitHub Issues](https://github.com/langgenius/dify/issues)
