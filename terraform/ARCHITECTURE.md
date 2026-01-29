# Dify GCP アーキテクチャ概要

## システムアーキテクチャ

```
┌─────────────────────────────────────────────────────────────────────┐
│                          インターネット                                │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ HTTPS
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Google Cloud Load Balancer                        │
│                   (SSL/TLS Termination)                             │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │
                ┌─────────────────┴─────────────────┐
                │                                   │
                ▼                                   ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│     Ingress Controller        │   │     Managed Certificate       │
│      (GKE Ingress)           │   │    (Google-managed SSL)       │
└───────────────────────────────┘   └───────────────────────────────┘
                │
                │ VPC Network (10.0.0.0/16)
                │
┌───────────────┴───────────────────────────────────────────────────┐
│                  Google Kubernetes Engine (GKE)                    │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Application Tier                       │   │
│  │  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌───────────┐ │   │
│  │  │   Web   │  │   API   │  │  Worker  │  │Worker Beat│ │   │
│  │  │ (Next.js│  │ (Flask) │  │ (Celery) │  │  (Celery) │ │   │
│  │  │    x2)  │  │   x2)   │  │    x2)   │  │    x1)    │ │   │
│  │  └────┬────┘  └────┬────┘  └────┬─────┘  └─────┬─────┘ │   │
│  │       │            │            │              │        │   │
│  └───────┼────────────┼────────────┼──────────────┼────────┘   │
│          │            │            │              │            │
│  ┌───────┴────────────┴────────────┴──────────────┴────────┐   │
│  │                   Service Layer                          │   │
│  │  ┌──────────┐  ┌──────────┐  ┌────────┐  ┌──────────┐ │   │
│  │  │ Sandbox  │  │  Plugin  │  │  SSRF  │  │ Weaviate │ │   │
│  │  │ (x2)     │  │  Daemon  │  │ Proxy  │  │  (x1)    │ │   │
│  │  │          │  │  (x1)    │  │ (x2)   │  │          │ │   │
│  │  └──────────┘  └──────────┘  └────────┘  └──────────┘ │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Storage Layer                          │   │
│  │  ┌─────────────────┐  ┌──────────────────────────────┐  │   │
│  │  │ Persistent      │  │  GCS Mounted                 │  │   │
│  │  │ Volumes (PVC)   │  │  (via Workload Identity)     │  │   │
│  │  └─────────────────┘  └──────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
                │                              │
                │ Private Service Connect      │ VPC Peering
                │                              │
┌───────────────┴─────────┐    ┌──────────────┴──────────┐
│   Cloud SQL PostgreSQL  │    │  Memorystore for Redis  │
│   - Primary + Replica   │    │  - Version 6.x          │
│   - Auto Backup         │    │  - High Availability    │
│   - 100GB SSD           │    │  - 1GB Memory           │
└─────────────────────────┘    └─────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      External Services                               │
│  ┌──────────────┐  ┌─────────────┐  ┌──────────────────────────┐  │
│  │ Cloud        │  │ Cloud       │  │ Cloud Storage (GCS)      │  │
│  │ Monitoring   │  │ Logging     │  │ - File Storage           │  │
│  │              │  │             │  │ - Versioning Enabled     │  │
│  └──────────────┘  └─────────────┘  └──────────────────────────┘  │
│  ┌──────────────┐  ┌─────────────┐  ┌──────────────────────────┐  │
│  │ Secret       │  │ IAM &       │  │ Cloud NAT                │  │
│  │ Manager      │  │ Workload    │  │ (Egress Traffic)         │  │
│  │              │  │ Identity    │  │                          │  │
│  └──────────────┘  └─────────────┘  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## コンポーネント詳細

### 1. ネットワーク層

#### Cloud Load Balancer
- **役割**: HTTPS トラフィックの受け口、SSL/TLS 終端
- **機能**:
  - グローバル負荷分散
  - Google マネージド SSL 証明書
  - 自動スケーリング
  - DDoS 保護

#### VPC (Virtual Private Cloud)
- **CIDR**: 10.0.0.0/16
- **Pod CIDR**: 10.1.0.0/16
- **Service CIDR**: 10.2.0.0/16
- **機能**:
  - プライベートネットワーク
  - Service Networking (Cloud SQL, Redis 接続用)
  - Cloud NAT (外部アクセス用)

### 2. コンピュート層 (GKE)

#### Web Service
- **イメージ**: langgenius/dify-web:1.11.4
- **レプリカ数**: 2
- **リソース**: 256Mi-1Gi RAM, 100m-500m CPU
- **役割**: Next.js フロントエンドアプリケーション
- **ポート**: 3000

#### API Service
- **イメージ**: langgenius/dify-api:1.11.4
- **レプリカ数**: 2
- **リソース**: 512Mi-2Gi RAM, 250m-1000m CPU
- **役割**: Flask バックエンド API
- **ポート**: 5001
- **ヘルスチェック**: /health

#### Worker Service
- **イメージ**: langgenius/dify-api:1.11.4
- **レプリカ数**: 2
- **リソース**: 512Mi-2Gi RAM, 250m-1000m CPU
- **役割**: Celery 非同期タスク処理
- **キュー**: dataset, workflow, mail など

#### Worker Beat Service
- **イメージ**: langgenius/dify-api:1.11.4
- **レプリカ数**: 1
- **リソース**: 256Mi-512Mi RAM, 100m-500m CPU
- **役割**: Celery スケジューラー（定期タスク）

#### Sandbox Service
- **イメージ**: langgenius/dify-sandbox:0.2.12
- **レプリカ数**: 2
- **リソース**: 256Mi-1Gi RAM, 100m-500m CPU
- **役割**: Python/Node.js コード実行環境
- **ポート**: 8194

#### Plugin Daemon
- **イメージ**: langgenius/dify-plugin-daemon:0.5.2-local
- **レプリカ数**: 1
- **リソース**: 512Mi-2Gi RAM, 250m-1000m CPU
- **役割**: プラグイン管理とデバッグ
- **ポート**: 5002 (API), 5003 (Debug)

#### SSRF Proxy
- **イメージ**: ubuntu/squid:latest
- **レプリカ数**: 2
- **リソース**: 128Mi-512Mi RAM, 100m-500m CPU
- **役割**: SSRF 攻撃対策プロキシ
- **ポート**: 3128

#### Weaviate
- **イメージ**: semitechnologies/weaviate:1.27.0
- **レプリカ数**: 1
- **リソース**: 1Gi-4Gi RAM, 500m-2000m CPU
- **役割**: ベクトルデータベース
- **ストレージ**: 100GB Persistent Volume
- **ポート**: 8080 (HTTP), 50051 (gRPC)

### 3. データ層

#### Cloud SQL (PostgreSQL 15)
- **構成**: Regional (HA)
- **スペック**: 2 vCPU, 4GB RAM
- **ストレージ**: 100GB SSD
- **機能**:
  - 自動バックアップ (毎日 3:00)
  - Point-in-time リカバリ
  - プライベート IP 接続
  - SSL/TLS 強制
  - 30日間のバックアップ保持

#### Memorystore for Redis
- **バージョン**: Redis 6.x
- **メモリ**: 1GB
- **ティア**: Basic (または Standard HA)
- **接続**: VPC Peering 経由
- **機能**:
  - メモリキャッシュ
  - Celery ブローカー
  - セッション管理

#### Cloud Storage (GCS)
- **ロケーション**: ASIA (マルチリージョン)
- **ストレージクラス**: Standard
- **機能**:
  - ユーザーファイル保存
  - バージョニング有効
  - ライフサイクル管理 (90日後 Nearline, 365日後 Coldline)
  - CORS 設定済み
  - Workload Identity によるアクセス

### 4. セキュリティ

#### IAM & Workload Identity
- **GKE Service Account**: Pod が GCP リソースにアクセス
- **権限**:
  - Cloud SQL Client
  - Storage Object Admin
  - Secret Manager Secret Accessor
  - Logging Writer
  - Monitoring Metric Writer

#### Secret Manager
- **保存されるシークレット**:
  - データベースパスワード
  - アプリケーションシークレットキー
  - API キー（Sandbox, Weaviate など）
  - Redis 認証情報

#### Network Security
- **Firewall ルール**:
  - 内部トラフィック許可
  - SSH (IAP 経由のみ)
  - HTTP/HTTPS (Load Balancer から)
- **Private Cluster**: マスターノードはプライベート
- **Network Policy**: Pod 間通信制御

### 5. 可観測性

#### Cloud Monitoring
- **メトリクス収集**:
  - GKE クラスターメトリクス
  - Pod/Container メトリクス
  - Cloud SQL パフォーマンス
  - Redis 使用状況
- **アラート**:
  - リソース使用率
  - エラー率
  - レイテンシ

#### Cloud Logging
- **ログ収集**:
  - アプリケーションログ
  - システムログ
  - 監査ログ
- **保持期間**: 30日（カスタマイズ可能）

## データフロー

### 1. ユーザーリクエスト
```
User → Load Balancer → Ingress → Web Service (3000) → 
                                ↓
                               API Service (5001) →
                                ↓
                        Cloud SQL / Redis / GCS
```

### 2. 非同期タスク
```
API Service → Redis (Broker) → Worker → Cloud SQL / GCS
                              ↓
                        Worker Beat (Scheduler)
```

### 3. ベクトル検索
```
API → Weaviate (8080/50051) → Persistent Storage
```

### 4. コード実行
```
API → SSRF Proxy → Sandbox (8194) → Isolated Execution
```

## スケーラビリティ

### 水平スケーリング
- **GKE Autoscaling**: 1-10 ノード
- **HPA (Horizontal Pod Autoscaler)**:
  - API: CPU 使用率 70% でスケール
  - Worker: キュー長でスケール
  - Web: CPU 使用率 70% でスケール

### 垂直スケーリング
- **Cloud SQL**: インスタンスサイズ変更（ダウンタイムあり）
- **Redis**: メモリサイズ変更（ダウンタイムあり）
- **GKE Node**: マシンタイプ変更

## 高可用性

### ゾーン分散
- GKE ノード: 複数ゾーンに分散
- Cloud SQL: Regional（自動フェイルオーバー）
- Load Balancer: グローバル

### レプリケーション
- Web: 2 レプリカ
- API: 2 レプリカ
- Worker: 2 レプリカ
- Sandbox: 2 レプリカ

### バックアップ
- Cloud SQL: 毎日自動バックアップ + PITR
- GCS: バージョニング有効
- PVC: スナップショット機能

## ディザスタリカバリ

### RTO (Recovery Time Objective): 1-4 時間
- Cloud SQL リストア: 〜30分
- GKE 再構築: 〜30分
- アプリケーション再デプロイ: 〜15分

### RPO (Recovery Point Objective): 1 分
- Cloud SQL PITR: 1 分単位で復元可能
- GCS: リアルタイム同期

## 今後の拡張性

### マルチリージョン展開
- Cloud SQL レプリカ追加
- GCS マルチリージョンバケット
- Global Load Balancer の活用

### マイクロサービス化
- サービスメッシュ (Istio)
- サービス間認証 (mTLS)
- 分散トレーシング (Cloud Trace)

### CI/CD パイプライン
- Cloud Build
- Artifact Registry
- GitOps (ArgoCD)
