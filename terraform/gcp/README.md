# Dify GCP Terraform Deployment

このTerraformコードは、Google Cloud Platform (GCP)上にDifyアプリケーションをデプロイするためのインフラストラクチャを構築します。

## 構成要素

このTerraformコードは以下のリソースを作成します:

### 基本インフラストラクチャ
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

### オプション: pgvector対応Cloud SQL
- **pgvector拡張機能**: ベクトル類似性検索用の専用PostgreSQLインスタンス
- **パフォーマンス最適化**: ベクトル演算に最適化された設定
- **リードレプリカ**: 読み取りスケーリング用（オプション）

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

## クイックスタート

### 1. 変数ファイルの準備

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`を編集し、最低限以下の値を設定:

```hcl
project_id = "your-gcp-project-id"
region     = "asia-northeast1"
zone       = "asia-northeast1-a"

# ドメイン名がある場合（推奨）
domain_name = "dify.example.com"

# または自己署名証明書用の設定
# domain_name     = ""
# ssl_certificate = file("certificate.pem")
# ssl_private_key = file("private-key.pem")

# SSHキー（オプション）
ssh_public_key = "ssh-rsa AAAAB3... your-email@example.com"

# データベースパスワード（空の場合は自動生成）
db_password = ""
```

### 2. デプロイ

```bash
# 初期化
terraform init

# プランの確認
terraform plan

# デプロイ実行
terraform apply
```

### 3. デプロイ完了後

```bash
# 出力情報の確認
terraform output

# ブラウザでアクセス
# https://<load_balancer_ip> または https://your-domain.com
```

## 詳細設定

### pgvectorの有効化

ベクトル類似性検索が必要な場合、専用のCloud SQLインスタンスを作成できます:

```hcl
# terraform.tfvars に追加
enable_pgvector = true

# オプション: カスタム設定
pgvector_tier = "db-custom-4-16384"  # 4 vCPU, 16GB RAM
pgvector_disk_size = 100
pgvector_db_name = "dify_vector"
pgvector_db_user = "dify_vector"
pgvector_db_password = ""  # 空の場合は自動生成
```

pgvectorを有効化した後、拡張機能をインストール:

```bash
# Cloud SQL Proxyを使用
./cloud-sql-proxy $(terraform output -raw pgvector_connection_name)

# 別ターミナルで
export PGPASSWORD=$(terraform output -raw pgvector_database_password)
psql -h 127.0.0.1 -U $(terraform output -raw pgvector_database_user) \
  -d $(terraform output -raw pgvector_database_name) \
  -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### SSL証明書の設定

#### オプション1: Google管理SSL証明書（推奨）

```hcl
domain_name = "dify.example.com"
```

DNSレコードを設定:
```
A    dify.example.com    <LOAD_BALANCER_IP>
```

証明書のプロビジョニングは最大15分かかります。

#### オプション2: 自己署名証明書

```bash
# 証明書の生成
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout private-key.pem -out certificate.pem \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Dify/CN=dify.local"
```

```hcl
domain_name     = ""
ssl_certificate = file("certificate.pem")
ssl_private_key = file("private-key.pem")
```

## Difyのデプロイ

### VMにSSH接続

```bash
# Terraformの出力から取得
terraform output ssh_command

# または直接
gcloud compute ssh dify-vm --zone asia-northeast1-a --project your-project-id
```

### Difyのセットアップ

```bash
# 作業ディレクトリに移動
cd /opt/dify

# Difyリポジトリをクローン
git clone https://github.com/langgenius/dify.git
cd dify/docker

# 環境変数を設定
cp .env.example .env
nano .env

# 以下の設定を更新:
# DB_USERNAME=<terraform output database_user>
# DB_PASSWORD=<terraform output -raw database_password>
# DB_HOST=<terraform output -raw cloudsql_private_ip>
# DB_PORT=5432
# DB_DATABASE=<terraform output database_name>

# pgvectorを使用する場合は追加:
# VECTOR_STORE=pgvector
# PGVECTOR_HOST=<terraform output -raw pgvector_private_ip>
# PGVECTOR_PORT=5432
# PGVECTOR_USER=<terraform output pgvector_database_user>
# PGVECTOR_PASSWORD=<terraform output -raw pgvector_database_password>
# PGVECTOR_DATABASE=<terraform output pgvector_database_name>

# Docker Composeで起動
docker-compose up -d

# ログを確認
docker-compose logs -f
```

## pgvectorの使用例

### テーブルの作成

```sql
-- 1536次元のベクトル列を持つテーブル（OpenAI embeddings用）
CREATE TABLE documents (
  id BIGSERIAL PRIMARY KEY,
  content TEXT,
  embedding vector(1536),
  metadata JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- HNSWインデックスの作成（推奨）
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- または IVFFlatインデックス（大規模データセット用）
-- CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops)
-- WITH (lists = 100);
```

### 類似検索

```sql
-- コサイン類似度による検索
SELECT id, content, 1 - (embedding <=> '[0.1, 0.2, ...]'::vector) AS similarity
FROM documents
ORDER BY embedding <=> '[0.1, 0.2, ...]'::vector
LIMIT 10;

-- L2距離による検索
SELECT id, content, embedding <-> '[0.1, 0.2, ...]'::vector AS distance
FROM documents
ORDER BY embedding <-> '[0.1, 0.2, ...]'::vector
LIMIT 10;
```

## パフォーマンスチューニング

### 推奨インスタンスサイズ

| ユースケース | VM | Cloud SQL | pgvector (オプション) |
|------------|-----|-----------|---------------------|
| 開発/テスト | n1-standard-2 | db-custom-2-7680 | db-custom-2-8192 |
| 小規模本番 | n1-standard-2 | db-custom-2-7680 | db-custom-4-16384 |
| 中規模本番 | n1-standard-4 | db-custom-4-15360 | db-custom-8-32768 |
| 大規模本番 | n1-standard-8 | db-custom-8-30720 | db-custom-16-65536 |

### pgvectorのパフォーマンス設定

Cloud SQLではインスタンスタイプ（tier）に応じてメモリ設定が自動的に最適化されます。手動でのメモリチューニングは不要です。

設定可能なパフォーマンスパラメータ:

```hcl
pgvector_max_connections = "200"  # 最大接続数
pgvector_tier = "db-custom-4-16384"  # インスタンスサイズ（4 vCPU, 16GB RAM）
```

**自動管理されるパラメータ:**
- `shared_buffers`: インスタンスRAMの約25%に自動設定
- `effective_cache_size`: インスタンスRAMの約75%に自動設定
- `maintenance_work_mem`: インデックス作成用に自動最適化
- `work_mem`: クエリ実行用に自動最適化

## 高可用性構成

### Cloud SQLの高可用性

```hcl
# main.tfの google_sql_database_instance リソースで
availability_type = "REGIONAL"  # ZONALからREGIONALに変更
```

### pgvectorのリードレプリカ

```hcl
pgvector_enable_read_replica = true
pgvector_replica_region = "us-central1"  # オプション: 別リージョン
pgvector_replica_tier = "db-custom-2-8192"  # オプション: 小さいマシンタイプ
```

## トラブルシューティング

### Cloud SQLへの接続確認

```bash
# VMからCloud SQLに接続テスト
gcloud compute ssh dify-vm --zone asia-northeast1-a

# PostgreSQLクライアントをインストール
sudo apt-get update
sudo apt-get install -y postgresql-client

# 基本DBに接続
psql "$(terraform output -raw database_url)"

# pgvectorに接続（有効化している場合）
psql "$(terraform output -raw pgvector_database_url)"
```

### Cloud SQLの状態確認

```bash
# インスタンスの一覧
gcloud sql instances list

# インスタンスの詳細
gcloud sql instances describe $(terraform output -raw cloudsql_instance_name)

# pgvectorインスタンスの詳細（有効化している場合）
gcloud sql instances describe $(terraform output -raw pgvector_instance_name)
```

### ヘルスチェックが失敗する

```bash
# VMにSSH接続
gcloud compute ssh dify-vm --zone asia-northeast1-a

# Dockerコンテナの状態確認
cd /opt/dify/dify/docker
docker-compose ps

# ログ確認
docker-compose logs -f
```

### SSL証明書のプロビジョニング確認

```bash
# 証明書の状態確認
gcloud compute ssl-certificates list
gcloud compute ssl-certificates describe dify-ssl-cert --global
```

### pgvector拡張機能の確認

```sql
-- 利用可能な拡張機能を確認
SELECT * FROM pg_available_extensions WHERE name = 'vector';

-- インストール済み拡張機能を確認
\dx vector

-- PostgreSQLバージョンを確認（11以降が必要）
SELECT version();
```

### パフォーマンス問題（pgvector）

```sql
-- インデックスの使用状況を確認
EXPLAIN ANALYZE
SELECT * FROM documents
ORDER BY embedding <=> '[0.1, 0.2, ...]'::vector
LIMIT 10;

-- 統計情報の更新
ANALYZE documents;

-- インデックスの再構築
REINDEX INDEX <index_name>;
```

## セキュリティのベストプラクティス

1. **SSH接続の制限**: `ssh_source_ranges`を特定のIPに限定
   ```hcl
   ssh_source_ranges = ["203.0.113.0/24"]
   ```

2. **プライベートIP接続**: Cloud SQLはプライベートIPのみを使用
   ```hcl
   pgvector_enable_public_ip = false
   ```

3. **強力なパスワード**: 自動生成を使用するか、強力なパスワードを設定

4. **削除保護**: 本番環境では有効化
   ```hcl
   deletion_protection = true
   pgvector_deletion_protection = true
   ```

5. **バックアップ**: 定期的なバックアップを有効化
   ```hcl
   cloudsql_backup_enabled = true
   pgvector_backup_enabled = true
   ```

6. **監査ログ**: Cloud Auditログを有効化
   ```hcl
   cloudsql.enable_pgaudit = "on"
   ```

## モニタリング

### Cloud Monitoringでの確認項目

- **Database connections**: 接続数の監視
- **CPU utilization**: CPUの使用率
- **Memory utilization**: メモリの使用率
- **Disk utilization**: ディスクの使用率
- **Replication lag**: レプリカの遅延（リードレプリカ使用時）

### Query Insightsの活用

```bash
# GCPコンソールで確認
# Cloud SQL > [インスタンス名] > Query Insights
```

Query Insightsを有効化:
```hcl
pgvector_query_insights_enabled = true
```

## コスト最適化

### 開発環境

```hcl
# 小さいインスタンス
machine_type = "n1-standard-1"
cloudsql_tier = "db-custom-1-3840"
pgvector_tier = "db-custom-2-8192"

# バックアップを無効化
cloudsql_backup_enabled = false
pgvector_backup_enabled = false

# 削除保護を無効化
deletion_protection = false
pgvector_deletion_protection = false

# Query Insightsを無効化
pgvector_query_insights_enabled = false
```

### 本番環境

```hcl
# 適切なサイズのインスタンス
machine_type = "n1-standard-2"
cloudsql_tier = "db-custom-2-7680"
pgvector_tier = "db-custom-4-16384"

# バックアップを有効化
cloudsql_backup_enabled = true
pgvector_backup_enabled = true
pgvector_backup_retention_count = 7

# 削除保護を有効化
deletion_protection = true
pgvector_deletion_protection = true

# Query Insightsを有効化
pgvector_query_insights_enabled = true

# 高可用性（オプション）
availability_type = "REGIONAL"
pgvector_availability_type = "REGIONAL"
```

### その他のコスト削減

- **Committed Use Discounts**: 1年または3年の契約で割引
- **スケジューリング**: 夜間や週末にVMを停止
- **ディスク最適化**: 必要なサイズのみを使用
- **リージョン選択**: コストの低いリージョンを選択

## リソースの削除

```bash
# 削除保護を無効化
# terraform.tfvars または main.tf で deletion_protection = false に設定

terraform apply

# すべてのリソースを削除
terraform destroy
```

## 変数一覧

### 基本設定
- `project_id`: GCPプロジェクトID（必須）
- `region`: リージョン（デフォルト: asia-northeast1）
- `zone`: ゾーン（デフォルト: asia-northeast1-a）
- `prefix`: リソース名のプレフィックス（デフォルト: dify）

### ネットワーク設定
- `subnet_cidr`: サブネットのCIDR範囲
- `ssh_source_ranges`: SSH接続を許可するCIDR範囲

### VM設定
- `machine_type`: VMのマシンタイプ
- `disk_size_gb`: ブートディスクのサイズ（GB）
- `ssh_user`: SSHユーザー名
- `ssh_public_key`: SSH公開鍵

### SSL設定
- `domain_name`: ドメイン名（Google管理証明書用）
- `ssl_certificate`: 自己署名証明書（PEM形式）
- `ssl_private_key`: 自己署名証明書の秘密鍵

### Cloud SQL設定
- `cloudsql_tier`: Cloud SQLのマシンタイプ
- `cloudsql_disk_size`: ディスクサイズ（GB）
- `cloudsql_database_version`: PostgreSQLバージョン
- `cloudsql_backup_enabled`: バックアップの有効化
- `db_name`: データベース名
- `db_user`: データベースユーザー名
- `db_password`: データベースパスワード

### pgvector設定
- `enable_pgvector`: pgvectorインスタンスの有効化（デフォルト: false）
- `pgvector_tier`: pgvectorのマシンタイプ
- `pgvector_disk_size`: ディスクサイズ（GB）
- `pgvector_database_version`: PostgreSQLバージョン
- `pgvector_db_name`: データベース名
- `pgvector_db_user`: データベースユーザー名
- `pgvector_db_password`: データベースパスワード
- 他の設定は`terraform.tfvars.example`を参照

## 参考リンク

- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Dify Documentation](https://docs.dify.ai/)
- [GCP Load Balancer Documentation](https://cloud.google.com/load-balancing/docs)
- [Cloud SQL for PostgreSQL](https://cloud.google.com/sql/docs/postgres)
- [pgvector GitHub](https://github.com/pgvector/pgvector)
- [PostgreSQL Extensions on Cloud SQL](https://cloud.google.com/sql/docs/postgres/extensions)

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
