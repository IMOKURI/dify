#!/bin/bash
set -e

# Update system
apt-get update
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    jq \
    postgresql-client

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl enable docker
systemctl start docker

# Install Docker Compose
DOCKER_COMPOSE_VERSION="v2.24.5"
curl -L "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directory
mkdir -p /opt/dify
cd /opt/dify

# Create docker-compose.yml for Dify services
cat > /opt/dify/docker-compose.yml <<'EOF'
version: '3.8'

x-shared-env: &shared-api-worker-env
  LOG_LEVEL: ${log_level}
  SECRET_KEY: ${secret_key}
  INIT_PASSWORD: ${init_password}
  CONSOLE_API_URL: ${console_api_url}
  CONSOLE_WEB_URL: ${console_web_url}
  SERVICE_API_URL: ${service_api_url}
  APP_API_URL: ${app_api_url}
  APP_WEB_URL: ${app_web_url}
  FILES_URL: ${files_url}
  MIGRATION_ENABLED: "true"
  DEPLOY_ENV: PRODUCTION
  
  # Database configuration (Cloud SQL)
  DB_TYPE: postgresql
  DB_HOST: ${db_host}
  DB_PORT: ${db_port}
  DB_USERNAME: ${db_username}
  DB_PASSWORD: ${db_password}
  DB_DATABASE: ${db_database}
  SQLALCHEMY_POOL_SIZE: 30
  SQLALCHEMY_MAX_OVERFLOW: 10
  SQLALCHEMY_POOL_RECYCLE: 3600
  
  # Redis configuration (Memorystore)
  REDIS_HOST: ${redis_host}
  REDIS_PORT: ${redis_port}
  REDIS_PASSWORD: ${redis_password}
  REDIS_DB: 0
  REDIS_USE_SSL: "false"
  CELERY_BROKER_URL: redis://:${redis_password}@${redis_host}:${redis_port}/1
  
  # Vector store configuration (Cloud SQL with pgvector)
  VECTOR_STORE: pgvector
  PGVECTOR_HOST: ${pgvector_host}
  PGVECTOR_PORT: ${pgvector_port}
  PGVECTOR_USER: ${pgvector_user}
  PGVECTOR_PASSWORD: ${pgvector_password}
  PGVECTOR_DATABASE: ${pgvector_database}
  
  # Storage configuration (Cloud Storage)
  STORAGE_TYPE: opendal
  OPENDAL_SCHEME: gcs
  GOOGLE_STORAGE_BUCKET_NAME: ${storage_bucket}
  GOOGLE_STORAGE_SERVICE_ACCOUNT_JSON_BASE64: ${service_account_json_base64}
  
  # Code execution
  CODE_EXECUTION_ENDPOINT: http://sandbox:8194
  CODE_EXECUTION_API_KEY: dify-sandbox
  
  # SSRF proxy
  SSRF_PROXY_HTTP_URL: http://ssrf_proxy:3128
  SSRF_PROXY_HTTPS_URL: http://ssrf_proxy:3128
  
  # Plugin daemon
  PLUGIN_DAEMON_URL: http://plugin_daemon:5002
  PLUGIN_DAEMON_KEY: lYkiYYT6owG+71oLerGzA7GXCgOT++6ovaezWAjpCjf+Sjc3ZtU+qUEi
  PLUGIN_DIFY_INNER_API_KEY: QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1
  PLUGIN_DIFY_INNER_API_URL: http://api:5001

services:
  # API service
  api:
    image: langgenius/dify-api:${dify_version}
    restart: always
    environment:
      <<: *shared-api-worker-env
      MODE: api
    volumes:
      - /opt/dify/storage:/app/api/storage
    networks:
      - ssrf_proxy_network
      - default

  # Worker service
  worker:
    image: langgenius/dify-api:${dify_version}
    restart: always
    environment:
      <<: *shared-api-worker-env
      MODE: worker
    volumes:
      - /opt/dify/storage:/app/api/storage
    networks:
      - ssrf_proxy_network
      - default

  # Worker beat service
  worker_beat:
    image: langgenius/dify-api:${dify_version}
    restart: always
    environment:
      <<: *shared-api-worker-env
      MODE: beat
    networks:
      - ssrf_proxy_network
      - default

  # Frontend web application
  web:
    image: langgenius/dify-web:${dify_version}
    restart: always
    environment:
      CONSOLE_API_URL: ${console_api_url}
      APP_API_URL: ${app_api_url}
      NEXT_TELEMETRY_DISABLED: 1

  # Sandbox
  sandbox:
    image: langgenius/dify-sandbox:0.2.12
    restart: always
    environment:
      API_KEY: dify-sandbox
      GIN_MODE: release
      WORKER_TIMEOUT: 15
      ENABLE_NETWORK: "true"
      HTTP_PROXY: http://ssrf_proxy:3128
      HTTPS_PROXY: http://ssrf_proxy:3128
      SANDBOX_PORT: 8194
    volumes:
      - /opt/dify/sandbox/dependencies:/dependencies
      - /opt/dify/sandbox/conf:/conf
    networks:
      - ssrf_proxy_network

  # Plugin daemon
  plugin_daemon:
    image: langgenius/dify-plugin-daemon:0.5.2-local
    restart: always
    environment:
      <<: *shared-api-worker-env
      DB_DATABASE: dify_plugin
      SERVER_PORT: 5002
      SERVER_KEY: lYkiYYT6owG+71oLerGzA7GXCgOT++6ovaezWAjpCjf+Sjc3ZtU+qUEi
      DIFY_INNER_API_URL: http://api:5001
      DIFY_INNER_API_KEY: QaHbTe77CtuXmsfyhR7+vRjI/+XbV1AaFy691iy+kGDv2Jvy0/eAh8Y1
      PLUGIN_STORAGE_TYPE: gcs
      PLUGIN_STORAGE_OSS_BUCKET: ${storage_bucket}
      GOOGLE_STORAGE_SERVICE_ACCOUNT_JSON_BASE64: ${service_account_json_base64}
    volumes:
      - /opt/dify/plugin_daemon:/app/storage

  # SSRF proxy
  ssrf_proxy:
    image: ubuntu/squid:latest
    restart: always
    volumes:
      - /opt/dify/squid.conf:/etc/squid/squid.conf
    networks:
      - ssrf_proxy_network
      - default

  # Nginx reverse proxy
  nginx:
    image: nginx:latest
    restart: always
    ports:
      - "80:80"
    volumes:
      - /opt/dify/nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - api
      - web

networks:
  ssrf_proxy_network:
    driver: bridge
    internal: true
EOF

# Create squid.conf
mkdir -p /opt/dify
cat > /opt/dify/squid.conf <<'EOF'
http_port 3128

acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16

acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl Safe_ports port 8194
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow localnet
http_access allow localhost
http_access deny all

coredump_dir /var/spool/squid
refresh_pattern ^ftp: 1440 20% 10080
refresh_pattern ^gopher: 1440 0% 1440
refresh_pattern -i (/cgi-bin/|\?) 0 0% 0
refresh_pattern . 0 20% 4320
EOF

# Create nginx.conf
cat > /opt/dify/nginx.conf <<'EOF'
events {
    worker_connections 1024;
}

http {
    upstream api {
        server api:5001;
    }

    upstream web {
        server web:3000;
    }

    server {
        listen 80;
        server_name _;
        client_max_body_size 100M;

        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        location /console/api {
            proxy_pass http://api;
            proxy_set_header Host $$host;
            proxy_set_header X-Real-IP $$remote_addr;
            proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $$scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        location /api {
            proxy_pass http://api;
            proxy_set_header Host $$host;
            proxy_set_header X-Real-IP $$remote_addr;
            proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $$scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        location /v1 {
            proxy_pass http://api;
            proxy_set_header Host $$host;
            proxy_set_header X-Real-IP $$remote_addr;
            proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $$scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        location /files {
            proxy_pass http://api;
            proxy_set_header Host $$host;
            proxy_set_header X-Real-IP $$remote_addr;
            proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $$scheme;
        }

        location / {
            proxy_pass http://web;
            proxy_set_header Host $$host;
            proxy_set_header X-Real-IP $$remote_addr;
            proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $$scheme;
        }
    }
}
EOF

# Create storage directories
mkdir -p /opt/dify/storage
mkdir -p /opt/dify/sandbox/dependencies
mkdir -p /opt/dify/sandbox/conf
mkdir -p /opt/dify/plugin_daemon
chown -R 1001:1001 /opt/dify/storage

# Enable pgvector extension
echo "Enabling pgvector extension..."
export PGPASSWORD='${pgvector_password}'
psql -h ${pgvector_host} -U ${pgvector_user} -d ${pgvector_database} -c "CREATE EXTENSION IF NOT EXISTS vector;" || true
unset PGPASSWORD

# Start services
cd /opt/dify
docker-compose up -d

# Setup log rotation
cat > /etc/logrotate.d/dify <<'EOF'
/opt/dify/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 root root
    sharedscripts
}
EOF

echo "Dify installation completed!"
