# Dify アーキテクチャ図

```mermaid
graph TB
    subgraph "外部アクセス"
        Client[クライアント<br/>ブラウザ/API]
    end

    subgraph "リバースプロキシ層"
        nginx[NGINX<br/>:80/:443<br/>リバースプロキシ]
        certbot[Certbot<br/>SSL証明書管理]
    end

    subgraph "アプリケーション層"
        web[Web<br/>Next.js Frontend<br/>langgenius/dify-web]
        api[API<br/>Flask Backend<br/>langgenius/dify-api<br/>MODE: api]
        worker[Worker<br/>Celery Worker<br/>langgenius/dify-api<br/>MODE: worker]
        worker_beat[Worker Beat<br/>Celery Beat<br/>langgenius/dify-api<br/>MODE: beat]
        plugin_daemon[Plugin Daemon<br/>:5002<br/>langgenius/dify-plugin-daemon]
    end

    subgraph "サンドボックス実行環境"
        sandbox[DifySandbox<br/>:8194<br/>コード実行環境<br/>langgenius/dify-sandbox]
    end

    subgraph "データベース層"
        db_postgres[(PostgreSQL<br/>:5432<br/>メインDB<br/>profile: postgresql)]
    end

    subgraph "キャッシュ/メッセージキュー"
        redis[(Redis<br/>:6379<br/>キャッシュ<br/>Celeryブローカー)]
    end

    subgraph "ベクトルストア"
        weaviate[(Weaviate<br/>:8080<br/>profile: weaviate)]
    end

    subgraph "セキュリティ/プロキシ層"
        ssrf_proxy[SSRF Proxy<br/>:3128<br/>Squid<br/>SSRFプロテクション]
    end

    subgraph "初期化"
        init[init_permissions<br/>ストレージ権限設定<br/>busybox]
    end

    subgraph "ETLサービス (オプション)"
        unstructured[Unstructured<br/>ドキュメント処理<br/>profile: unstructured]
    end

    %% クライアント接続
    Client --> nginx

    %% Nginx ルーティング
    nginx --> web
    nginx --> api
    certbot -.->|SSL証明書| nginx

    %% API層の接続
    web -.->|API呼び出し| api
    api --> db_postgres
    api --> redis
    api --> weaviate
    api --> plugin_daemon

    %% Worker接続
    worker --> redis
    worker --> db_postgres
    worker --> weaviate

    %% Beat接続
    worker_beat --> redis
    worker_beat --> db_postgres

    %% Plugin Daemon接続
    plugin_daemon --> db_postgres
    plugin_daemon --> api

    %% Redis: Celeryブローカー
    redis -.->|タスクキュー| worker
    redis -.->|スケジュール| worker_beat

    %% SSRF Proxy接続
    api ---|SSRFプロテクション| ssrf_proxy
    worker ---|SSRFプロテクション| ssrf_proxy
    sandbox ---|プロキシ経由| ssrf_proxy
    ssrf_proxy -.->|リバースプロキシ| sandbox

    %% Sandbox接続
    api --> sandbox
    worker --> sandbox

    %% 初期化依存
    init -.->|初回のみ実行| api
    init -.->|初回のみ実行| worker

    %% ETL
    api -.->|オプション| unstructured
    worker -.->|オプション| unstructured

    %% ネットワークセグメント
    classDef proxyLayer fill:#e1f5ff,stroke:#01579b
    classDef appLayer fill:#fff3e0,stroke:#e65100
    classDef dataLayer fill:#f3e5f5,stroke:#4a148c
    classDef cacheLayer fill:#e8f5e9,stroke:#1b5e20
    classDef vectorLayer fill:#fce4ec,stroke:#880e4f
    classDef securityLayer fill:#fff9c4,stroke:#f57f17
    classDef initLayer fill:#eceff1,stroke:#37474f

    class nginx,certbot proxyLayer
    class web,api,worker,worker_beat,plugin_daemon,sandbox appLayer
    class db_postgres dataLayer
    class redis cacheLayer
    class weaviate vectorLayer
    class ssrf_proxy securityLayer
    class init initLayer

    %% ネットワークセグメント注釈
    style Client fill:#ffffff,stroke:#333,stroke-width:2px
```

## 主要コンポーネント

### 1. **リバースプロキシ層**
- **NGINX**: すべての外部リクエストを受け付け、WebフロントエンドとAPIバックエンドにルーティング
- **Certbot**: SSL/TLS証明書の自動取得と更新（オプション）

### 2. **アプリケーション層**
- **Web (Next.js)**: ユーザーインターフェース
- **API (Flask)**: RESTful APIサーバー
- **Worker (Celery)**: バックグラウンドタスク処理（データセット、ワークフロー、メールなど）
- **Worker Beat (Celery Beat)**: 定期タスクのスケジューラー
- **Plugin Daemon**: プラグイン管理とリモートインストール

### 3. **サンドボックス実行環境**
- **DifySandbox**: 安全なコード実行環境、SSRF Proxyを経由して外部アクセスを制限

### 4. **データベース層**
- **PostgreSQL** (profile: postgresql): 主データベース

### 5. **キャッシュ/メッセージキュー**
- **Redis**: セッションキャッシュおよびCeleryのメッセージブローカー

### 6. **ベクトルストア**
- **Weaviate**: ベクトル検索エンジン（埋め込みベクトルの保存と検索）

### 7. **セキュリティ層**
- **SSRF Proxy (Squid)**: Server-Side Request Forgery攻撃を防ぐためのプロキシ
  - サンドボックスとの専用ネットワーク（ssrf_proxy_network）で隔離
  - 外部ネットワークへの直接アクセスを制限

### 8. **初期化/ユーティリティ**
- **init_permissions**: ストレージディレクトリの権限設定（初回のみ）
- **Unstructured** (オプション): ドキュメントETL処理

## ネットワーク構成

### デフォルトネットワーク
ほとんどのサービスがこのネットワークに接続

### ssrf_proxy_network (内部専用)
- Sandbox、API、Worker、SSRF Proxyが接続
- 外部へのアクセスが制限された隔離ネットワーク
- セキュリティ保護のための重要な分離層

## データフロー

1. **ユーザーリクエスト**: Client → NGINX → Web/API
2. **API処理**: API → PostgreSQL + Redis + Weaviate
3. **非同期タスク**: API → Redis → Worker → DB/ストレージ
4. **定期タスク**: Worker Beat → Redis → Worker
5. **コード実行**: API/Worker → Sandbox (SSRF Proxy経由)
6. **プラグイン管理**: API ↔ Plugin Daemon ↔ PostgreSQL

## プロファイルによる起動

Docker Composeの`profiles`機能により、必要なサービスのみを起動:

```bash
# PostgreSQL + Weaviate構成
docker compose --profile postgresql --profile weaviate up
```

## ポート公開

- **80**: NGINX HTTP
- **443**: NGINX HTTPS
- **5002**: Plugin Daemon
- **5003**: Plugin Debugging
- **各種DB**: プロファイルに応じてポート公開

## ストレージボリューム

- `./volumes/app/storage`: アプリケーションファイル保存
- `./volumes/db/data`: PostgreSQLデータ
- `./volumes/redis/data`: Redisデータ
- `./volumes/weaviate`: Weaviateベクトルデータ
- `./volumes/plugin_daemon`: プラグインストレージ
- `./volumes/sandbox`: サンドボックス依存関係
