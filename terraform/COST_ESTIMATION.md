# コスト見積もりガイド

このドキュメントでは、Dify を GCP にデプロイした場合の月額コストの概算を示します。

## 前提条件

- リージョン: asia-northeast1 (東京)
- 稼働率: 24/7 (730時間/月)
- 環境: 本番環境（中規模）

## コスト内訳

### 1. GKE (Google Kubernetes Engine)

**クラスター管理費**: 無料（標準クラスター）

**ワーカーノード**:
- マシンタイプ: e2-standard-4 (4 vCPU, 16GB RAM)
- ノード数: 3台
- 月額コスト: 約 $180/ノード × 3 = **$540/月**

オートスケーリングを有効にすると、負荷に応じてコストが変動します。

### 2. Cloud SQL (PostgreSQL)

- インスタンスタイプ: db-custom-2-4096 (2 vCPU, 4GB RAM)
- 可用性: Regional (HA)
- ストレージ: 100GB SSD
- 月額コスト: 約 **$180/月**

### 3. Memorystore for Redis

- ティア: Basic (BASIC)
- メモリサイズ: 1GB
- 月額コスト: 約 **$40/月**

高可用性が必要な場合 (STANDARD_HA):
- 月額コスト: 約 **$80/月**

### 4. Cloud Storage

- バケット: Standard クラス
- ストレージ量: 100GB (推定)
- データ転送: 100GB/月 (推定)
- 月額コスト: 約 **$5-10/月**

### 5. Cloud Load Balancing

- HTTP(S) Load Balancer
- データ処理: 100GB/月
- 月額コスト: 約 **$20-30/月**

### 6. ネットワーク

- VPC: 無料
- Cloud NAT: 約 **$45/月**
- データ転送（外部向け）: 約 **$10-20/月**

### 7. その他のサービス

- Secret Manager: 約 **$2/月**
- Cloud Monitoring/Logging: 約 **$10-20/月**

## 合計月額コスト（推定）

| 項目 | 最小 | 標準 | 最大 |
|------|------|------|------|
| GKE ノード | $180 | $540 | $1,800 |
| Cloud SQL | $100 | $180 | $500 |
| Redis | $40 | $40 | $80 |
| Cloud Storage | $5 | $10 | $30 |
| Load Balancing | $20 | $25 | $50 |
| ネットワーク | $50 | $65 | $100 |
| その他 | $15 | $25 | $50 |
| **合計** | **$410** | **$885** | **$2,610** |

## コスト最適化の推奨事項

### 1. 開発/検証環境でのコスト削減

```hcl
# terraform.tfvars での設定例

# GKE
gke_machine_type = "e2-standard-2"  # より小さいマシンタイプ
gke_node_count = 1                   # ノード数削減
gke_min_node_count = 1
gke_max_node_count = 3

# Cloud SQL
db_tier = "db-custom-1-3840"        # より小さいインスタンス
db_availability_type = "ZONAL"      # ゾーン単位（HA無効）

# Redis
redis_tier = "BASIC"                 # Basic tier
redis_memory_size_gb = 1
```

**推定月額コスト**: $200-300

### 2. Preemptible VM の使用

開発環境では Preemptible VM を使用してコストを最大 80% 削減:

```hcl
# gke.tf に追加
node_config {
  preemptible  = true
  # ... その他の設定
}
```

**注意**: Preemptible VM は最大 24 時間で終了されるため、本番環境には不適切です。

### 3. Committed Use Discounts (CUD)

1年または3年のコミットメントで最大 57% の割引:

- 1年コミット: 約 25% 割引
- 3年コミット: 約 52% 割引

### 4. リージョンの選択

コストはリージョンによって異なります:

| リージョン | 相対コスト |
|-----------|-----------|
| us-central1 (Iowa) | 基準 (最安) |
| asia-northeast1 (Tokyo) | +15-20% |
| europe-west1 (Belgium) | +5-10% |

### 5. ストレージクラスの最適化

アクセス頻度に応じてストレージクラスを選択:

- **Standard**: 頻繁にアクセス（デフォルト）
- **Nearline**: 月1回程度のアクセス（約 50% 削減）
- **Coldline**: 年4回程度のアクセス（約 70% 削減）
- **Archive**: ほとんどアクセスしない（約 90% 削減）

### 6. オートスケーリングの活用

負荷に応じて自動的にスケール:

```hcl
gke_min_node_count = 1
gke_max_node_count = 10
```

ピーク時以外のコストを削減できます。

### 7. Cloud SQL のスケジューリング

開発環境では非営業時間にインスタンスを停止:

```bash
# 停止
gcloud sql instances patch INSTANCE_NAME --activation-policy=NEVER

# 起動
gcloud sql instances patch INSTANCE_NAME --activation-policy=ALWAYS
```

## モニタリングとアラート

予算アラートを設定して予期しないコスト増加を防ぎます:

```bash
gcloud billing budgets create \
  --billing-account=BILLING_ACCOUNT_ID \
  --display-name="Dify Monthly Budget" \
  --budget-amount=1000USD \
  --threshold-rule=percent=50 \
  --threshold-rule=percent=90 \
  --threshold-rule=percent=100
```

## コスト管理ツール

1. **Cloud Billing Dashboard**: リアルタイムのコスト確認
2. **Cloud Billing Reports**: 詳細なコスト分析
3. **Recommender**: コスト最適化の推奨事項
4. **Budget Alerts**: 予算超過時のアラート

## まとめ

- **小規模環境**: $200-400/月
- **中規模環境**: $500-900/月
- **大規模環境**: $1,000-3,000/月

実際のコストは使用量とトラフィックによって変動します。本番運用前に必ず GCP Pricing Calculator で見積もりを行ってください。

**GCP Pricing Calculator**: https://cloud.google.com/products/calculator
