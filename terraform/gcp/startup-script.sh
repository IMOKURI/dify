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
    unzip \
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

# Download Dify release from GitHub
# Get latest release version
DIFY_VERSION=$(curl -s https://api.github.com/repos/langgenius/dify/releases/latest | jq -r .tag_name)
echo "Downloading Dify version: $DIFY_VERSION"

# Download and extract release
curl -L "https://github.com/langgenius/dify/archive/refs/tags/$DIFY_VERSION.zip" -o dify.zip
unzip -q dify.zip
rm dify.zip

# Move contents to /opt/dify
mv dify-*/* .
rmdir dify-*/

# Enable pgvector extension
echo "Enabling pgvector extension..."
export PGPASSWORD='${pgvector_password}'
psql -h ${pgvector_host} -U ${pgvector_user} -d ${pgvector_database} -c "CREATE EXTENSION IF NOT EXISTS vector;" || true
unset PGPASSWORD

echo "Dify $DIFY_VERSION downloaded successfully to /opt/dify"
echo "Please configure and start Dify manually."
